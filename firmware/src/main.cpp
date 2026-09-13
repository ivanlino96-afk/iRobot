#include <Arduino.h>
#include <ArduinoJson.h>
#include <Adafruit_PWMServoDriver.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>

// Create include/secrets.h from secrets.example.h before flashing a device.
#if __has_include("secrets.h")
#include "secrets.h"
#else
constexpr char WIFI_SSID[] = "";
constexpr char WIFI_PASSWORD[] = "";
constexpr char MQTT_HOST[] = "";
constexpr uint16_t MQTT_PORT = 8883;
constexpr char ROBOT_ID[] = "UNPROVISIONED";
constexpr char MQTT_USERNAME[] = "";
constexpr char MQTT_PASSWORD[] = "";
#endif

#if __has_include("ca_cert.h")
#include "ca_cert.h"
#define AIROBOT_HAS_CA_CERT 1
#else
#define AIROBOT_HAS_CA_CERT 0
#endif

namespace {
constexpr uint8_t kServoCount = 8;
constexpr uint16_t kPwmFrequencyHz = 50;
constexpr bool kActuatorsEnabled = false;  // Must remain false until calibration is approved.
constexpr unsigned long kReconnectIntervalMs = 5000;

struct ServoCalibration {
  uint8_t pcaChannel;
  int16_t minDegrees;
  int16_t maxDegrees;
  int16_t homeDegrees;
  bool inverted;
  int16_t offsetDegrees;
};

// Placeholder profile. It must be replaced from the versioned configuration service.
ServoCalibration kServos[kServoCount] = {
    {0, 0, 180, 90, false, 0}, {1, 0, 180, 90, false, 0},
    {2, 0, 180, 90, true, 0},  {3, 0, 180, 90, false, 0},
    {4, 0, 180, 90, false, 0}, {5, 0, 180, 90, false, 0},
    {6, 0, 180, 90, false, 0}, {7, 0, 180, 90, false, 0},
};

WiFiClientSecure tlsClient;
PubSubClient mqttClient(tlsClient);
Adafruit_PWMServoDriver pwm;
unsigned long lastReconnectAttempt = 0;
String lastCommandId;

String topic(const char* suffix) {
  return String("airobot/v1/robots/") + ROBOT_ID + "/" + suffix;
}

bool withinLimits(uint8_t servoIndex, int value) {
  const ServoCalibration& servo = kServos[servoIndex];
  return value >= servo.minDegrees && value <= servo.maxDegrees;
}

uint16_t degreesToPulse(uint8_t servoIndex, int degrees) {
  const ServoCalibration& servo = kServos[servoIndex];
  int adjusted = degrees + servo.offsetDegrees;
  if (servo.inverted) adjusted = 180 - adjusted;
  adjusted = constrain(adjusted, 0, 180);
  return map(adjusted, 0, 180, 102, 512);  // To be calibrated per MG995 batch.
}

bool moveServo(uint8_t servoIndex, int degrees) {
  if (servoIndex >= kServoCount || !withinLimits(servoIndex, degrees)) return false;
  if (kActuatorsEnabled) pwm.setPWM(kServos[servoIndex].pcaChannel, 0, degreesToPulse(servoIndex, degrees));
  return true;
}

void publishStatus(const char* status, const char* commandId = nullptr, const char* reason = nullptr) {
  StaticJsonDocument<384> document;
  document["robotId"] = ROBOT_ID;
  document["status"] = status;
  document["actuatorsEnabled"] = kActuatorsEnabled;
  if (commandId) document["commandId"] = commandId;
  if (reason) document["reason"] = reason;
  char payload[384];
  serializeJson(document, payload, sizeof(payload));
  mqttClient.publish(topic("state").c_str(), payload, true);
}

void reject(const char* commandId, const char* reason) { publishStatus("rejected", commandId, reason); }

bool commandExpired(JsonObject command) {
  // A command without a validated expiry cannot move physical hardware.
  if (!command.containsKey("expiresAtEpochMs")) return true;
  const time_t now = time(nullptr);
  if (now < 1700000000) return true;  // NTP has not synchronized yet.
  const int64_t expiresAtMs = command["expiresAtEpochMs"] | 0LL;
  return expiresAtMs <= static_cast<int64_t>(now) * 1000;
}

void handleCommand(const byte* payload, unsigned int length) {
  StaticJsonDocument<1024> document;
  const DeserializationError error = deserializeJson(document, payload, length);
  if (error) { reject(nullptr, "invalid-json"); return; }
  JsonObject command = document.as<JsonObject>();
  const char* commandId = command["commandId"] | "";
  const char* type = command["type"] | "";
  // Emergency commands are accepted first and never wait for clock synchronization.
  if (!strcmp(type, "emergencyStop")) { publishStatus("emergency-stop", commandId); return; }
  if (!strlen(commandId) || commandExpired(command)) { reject(commandId, "missing-or-expired-command"); return; }
  if (lastCommandId == commandId) { publishStatus("duplicate", commandId); return; }
  lastCommandId = commandId;

  if (!strcmp(type, "goHome")) {
    for (uint8_t index = 0; index < kServoCount; ++index) moveServo(index, kServos[index].homeDegrees);
    publishStatus("home-target-accepted", commandId);
    return;
  }
  if (!strcmp(type, "moveServo")) {
    const uint8_t index = command["servoIndex"] | 255;
    const int degrees = command["degrees"] | -1000;
    if (!moveServo(index, degrees)) { reject(commandId, "servo-limit-or-index"); return; }
    publishStatus("servo-target-accepted", commandId);
    return;
  }
  // Cartesian planning is intentionally not activated until the calibrated profile
  // and joint-axis model are present on the device.
  if (!strcmp(type, "moveTcp")) { reject(commandId, "cartesian-profile-not-calibrated"); return; }
  reject(commandId, "unsupported-command");
}

void onMqttMessage(char* incomingTopic, byte* payload, unsigned int length) {
  if (String(incomingTopic) == topic("command")) handleCommand(payload, length);
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void connectMqtt() {
  if (mqttClient.connected() || WiFi.status() != WL_CONNECTED) return;
  if (millis() - lastReconnectAttempt < kReconnectIntervalMs) return;
  lastReconnectAttempt = millis();
  const String willTopic = topic("state");
  const char* willPayload = "{\"status\":\"offline\"}";
  if (mqttClient.connect(ROBOT_ID, MQTT_USERNAME, MQTT_PASSWORD, willTopic.c_str(), 1, true, willPayload)) {
    mqttClient.subscribe(topic("command").c_str(), 1);
    publishStatus("online");
  }
}
}  // namespace

void setup() {
  Serial.begin(115200);
  Wire.begin();
  pwm.begin();
  pwm.setPWMFreq(kPwmFrequencyHz);
#if AIROBOT_HAS_CA_CERT
  tlsClient.setCACert(BROKER_CA_CERT);
#else
  // Without the broker CA, the robot remains disconnected instead of downgrading TLS.
  Serial.println("MQTTS disabled: ca_cert.h is required");
#endif
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  connectWifi();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
}

void loop() {
  connectWifi();
#if AIROBOT_HAS_CA_CERT
  connectMqtt();
  mqttClient.loop();
#endif
}
