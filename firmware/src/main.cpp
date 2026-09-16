#include "protocol.hpp"
#include <Adafruit_PWMServoDriver.h>
#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <Wire.h>
#include <atomic>
#include <esp_timer.h>
#include <mbedtls/base64.h>
#include <mbedtls/pk.h>
#include <mbedtls/sha256.h>
#include <mqtt_client.h>
#if __has_include("secrets.h")
#include "secrets.h"
#else
constexpr char WIFI_SSID[] = "", WIFI_PASSWORD[] = "", MQTT_HOST[] = "",
               ROBOT_ID[] = "UNPROVISIONED", MQTT_USERNAME[] = "",
               MQTT_PASSWORD[] = "";
constexpr uint16_t MQTT_PORT = 8883;
#endif
#if __has_include("ca_cert.h") && __has_include("server_key.h")
#include "ca_cert.h"
#include "server_key.h"
#define PROVISIONED 1
#else
#define PROVISIONED 0
constexpr char BROKER_CA_CERT[] = "", SERVER_PUBLIC_KEY[] = "";
#endif
using namespace airobot;
namespace {
std::string randomId() {
  char b[33];
  for (int i = 0; i < 4; i++)
    snprintf(b + i * 8, 9, "%08x", esp_random());
  return b;
}
std::string sha256(const std::string &s) {
  uint8_t hash[32];
  mbedtls_sha256_ret(reinterpret_cast<const unsigned char *>(s.data()),
                     s.size(), hash, 0);
  char b[65];
  for (int i = 0; i < 32; i++)
    snprintf(b + i * 2, 3, "%02x", hash[i]);
  return b;
}
std::string decode64(std::string s) {
  std::replace(s.begin(), s.end(), '-', '+');
  std::replace(s.begin(), s.end(), '_', '/');
  while (s.size() % 4)
    s += '=';
  std::string out(s.size(), '\0');
  size_t size = 0;
  if (mbedtls_base64_decode(
          reinterpret_cast<unsigned char *>(&out[0]), out.size(), &size,
          reinterpret_cast<const unsigned char *>(s.data()), s.size()))
    return "";
  out.resize(size);
  return out;
}
bool signature(const std::string &token, Json &claims) {
  auto a = token.find('.'), b = token.find('.', a + 1);
  if (a == std::string::npos || b == std::string::npos || token.size() > 2048)
    return false;
  Json h;
  if (deserializeJson(h, decode64(token.substr(0, a))) || h["alg"] != "RS256")
    return false;
  auto sig = decode64(token.substr(b + 1));
  uint8_t hash[32];
  mbedtls_sha256_ret(reinterpret_cast<const unsigned char *>(token.data()), b,
                     hash, 0);
  mbedtls_pk_context pk;
  mbedtls_pk_init(&pk);
  bool ok =
      !mbedtls_pk_parse_public_key(
          &pk, reinterpret_cast<const unsigned char *>(SERVER_PUBLIC_KEY),
          strlen(SERVER_PUBLIC_KEY) + 1) &&
      mbedtls_pk_can_do(&pk, MBEDTLS_PK_RSA) &&
      !mbedtls_pk_verify(&pk, MBEDTLS_MD_SHA256, hash, 32,
                         reinterpret_cast<const unsigned char *>(sig.data()),
                         sig.size());
  mbedtls_pk_free(&pk);
  return ok &&
         !deserializeJson(claims, decode64(token.substr(a + 1, b - a - 1)));
}
uint64_t mono() { return esp_timer_get_time() / 1000; }
Runtime runtime(ROBOT_ID, randomId());
Preferences prefs;
Adafruit_PWMServoDriver pwm;
esp_mqtt_client_handle_t mqtt = nullptr;
std::atomic<bool> connected{false}, overflow{false};
QueueHandle_t incoming, normalQueue, emergencyQueue;
struct Message {
  std::string raw, token, claims;
  bool retained = false, emergency = false;
};
std::string prefix() {
  return std::string("airobot/v1/robots/") + ROBOT_ID + "/";
}
void publish(const char *suffix, Json &doc, bool retained = false,
             int qos = 1) {
  if (!mqtt || !connected)
    return;
  std::string s;
  serializeJson(doc, s);
  auto t = prefix() + suffix;
  esp_mqtt_client_enqueue(mqtt, t.c_str(), s.c_str(), s.size(), qos, retained,
                          true);
}
void status() {
  Json event;
  if (runtime.lifecycle(event))
    publish("ack", event);
  auto s = runtime.status();
  publish("state", s, true);
}
void mqttEvent(void *, esp_event_base_t, int32_t event, void *data) {
  auto e = static_cast<esp_mqtt_event_handle_t>(data);
  static Message *partial = nullptr;
  if (event == MQTT_EVENT_CONNECTED) {
    connected = true;
    esp_mqtt_client_enqueue(mqtt, (prefix() + "availability").c_str(), "online",
                            6, 1, true, true);
    for (auto suffix : {"command", "emergency", "config"})
      esp_mqtt_client_subscribe(mqtt, (prefix() + suffix).c_str(), 1);
  } else if (event == MQTT_EVENT_DISCONNECTED) {
    connected = false;
    if (partial) {
      delete partial;
      partial = nullptr;
    }
  } else if (event == MQTT_EVENT_DATA) {
    if (e->current_data_offset == 0) {
      delete partial;
      partial = nullptr;
      if (e->total_data_len <= 0 || e->total_data_len > 16384)
        return;
      std::string topic(e->topic, e->topic_len);
      if (topic != prefix() + "command" && topic != prefix() + "emergency" &&
          topic != prefix() + "config")
        return;
      partial = new Message;
      partial->emergency = topic == prefix() + "emergency";
      partial->retained = e->retain;
    }
    if (!partial)
      return;
    partial->raw.append(e->data, e->data_len);
    if (partial->raw.size() == size_t(e->total_data_len)) {
      if (xQueueSend(incoming, &partial, 0) != pdTRUE) {
        overflow = true;
        delete partial;
      }
      partial = nullptr;
    }
  }
}
void verificationTask(void *) {
  Message *m;
  for (;;) {
    if (xQueueReceive(incoming, &m, portMAX_DELAY) != pdTRUE)
      continue;
    Json command, claims;
    if (!m->retained && !deserializeJson(command, m->raw) &&
        textField(command["authorization"], 2048)) {
      m->token = command["authorization"].as<std::string>();
      if (signature(m->token, claims))
        serializeJson(claims, m->claims);
    }
    auto queue = m->emergency ? emergencyQueue : normalQueue;
    if (xQueueSend(queue, &m, 0) != pdTRUE) {
      overflow = true;
      delete m;
    }
  }
}
void process(Message *m) {
  const auto previousHash = runtime.core.profile.hash;
  runtime.verify = [&](const std::string &token, Json &claims) {
    return token == m->token && !m->claims.empty() &&
           !deserializeJson(claims, m->claims);
  };
  auto ack = runtime.handle(m->raw, m->retained, uint64_t(time(nullptr)) * 1000,
                            mono(), m->emergency);
  if (runtime.core.profile.hash != previousHash) {
    runtime.hardwareReady = false;
    runtime.simulation = true;
  }
  publish("ack", ack);
  delete m;
  runtime.verify = {};
  status();
}
bool pwmOk = false;
std::string serialLine;
int calibrationIndex = -1;
double calibrationPosition = 0, calibrationTarget = 0, calibrationVelocity = 0;
bool calibrationReference = false;
uint64_t calibrationBeat = 0;
void serialCommand(const std::string &line) {
  if (line == "status") {
    auto s = runtime.status();
    serializeJson(s, Serial);
    Serial.println();
    return;
  }
  if (line == "latch") {
    runtime.core.latch();
    runtime.latchId = randomId();
    runtime.resetNonce = randomId();
    runtime.invalidate();
    if (!runtime.persist("latch", runtime.latchId))
      runtime.faultActive = true;
    calibrationIndex = -1;
    status();
    return;
  }
  if (line.rfind("commission ", 0) == 0) {
    if (runtime.core.state != State::BOOT_LOCKED ||
        !runtime.core.profile.calibrated ||
        runtime.core.profile.simulationOnly ||
        line.substr(11) != runtime.core.profile.hash || !pwmOk) {
      Serial.println("Commission rejected: require calibrated hardware "
                     "profile/hash and PCA9685");
      return;
    }
    prefs.putString("commissioned", runtime.core.profile.hash.c_str());
    runtime.simulation = false;
    runtime.hardwareReady = true;
    Serial.println(
        "Hardware commissioned; confirm reference and enable from app");
    status();
    return;
  }
  if (line.rfind("calibrate ", 0) == 0) {
    if ((runtime.core.state != State::UNCALIBRATED &&
         runtime.core.state != State::BOOT_LOCKED) ||
        !runtime.core.profile.valid() || runtime.core.profile.simulationOnly ||
        !pwmOk || line.substr(10) != runtime.core.profile.hash) {
      Serial.println("Calibration rejected");
      return;
    }
    runtime.core.state = State::CALIBRATING;
    runtime.invalidate();
    calibrationIndex = -1;
    calibrationReference = false;
    calibrationBeat = mono();
    Serial.println("Calibration: support arm; use reference INDEX DEGREES, "
                   "then servo INDEX DEGREES; repeat keepalive");
    return;
  }
  if (runtime.core.state != State::CALIBRATING)
    return;
  if (line == "keepalive") {
    calibrationBeat = mono();
    return;
  }
  if (line == "end") {
    calibrationIndex = -1;
    runtime.core.state = State::UNCALIBRATED;
    runtime.core.referenced = false;
    status();
    return;
  }
  int i;
  double deg;
  if (sscanf(line.c_str(), "reference %d %lf", &i, &deg) == 2) {
    if (i < 0 || i > 7 || !std::isfinite(deg) ||
        deg < runtime.core.profile.servos[i].min ||
        deg > runtime.core.profile.servos[i].max)
      return;
    calibrationIndex = i;
    calibrationPosition = calibrationTarget = deg;
    calibrationVelocity = 0;
    calibrationReference = true;
    calibrationBeat = mono();
    Serial.println(
        "Reference recorded as operator estimate; no output written");
    return;
  }
  if (sscanf(line.c_str(), "servo %d %lf", &i, &deg) == 2 &&
      i == calibrationIndex && calibrationReference) {
    auto s = runtime.core.profile.servos[i];
    if (!std::isfinite(deg) || deg < s.min || deg > s.max ||
        fabs(deg - calibrationPosition) > 5)
      return;
    calibrationTarget = deg;
    calibrationBeat = mono();
  }
}
} // namespace
void setup() {
  Serial.begin(115200);
  incoming = xQueueCreate(6, sizeof(Message *));
  normalQueue = xQueueCreate(4, sizeof(Message *));
  emergencyQueue = xQueueCreate(2, sizeof(Message *));
  bool storage = prefs.begin("airobot", false);
  runtime.clock = mono;
  runtime.sha = sha256;
  runtime.random = randomId;
  runtime.persist = [](const std::string &key, const std::string &value) {
    return prefs.putString(key.c_str(), value.c_str()) == value.size();
  };
  Wire.begin(6, 7);
  Wire.setTimeOut(10);
  pwmOk = pwm.begin();
  if (pwmOk) {
    pwm.setPWMFreq(50);
    for (int i = 0; i < 16; i++)
      pwm.setPWM(i, 0, 4096);
  }
  auto body = prefs.getString("profile", "");
  if (body.length()) {
    Json p;
    Profile profile;
    profile.hash = sha256(body.c_str());
    if (!deserializeJson(p, body) && parseProfile(p, profile)) {
      runtime.core.configure(profile);
      runtime.profileJson = body.c_str();
    } else
      runtime.core.fault("stored-profile-invalid");
  }
  auto latch = prefs.getString("latch", "");
  if (latch.length()) {
    runtime.core.latch();
    runtime.latchId = latch.c_str();
    runtime.resetNonce = randomId();
  }
  runtime.hardwareReady =
      pwmOk && runtime.core.profile.valid() &&
      runtime.core.profile.calibrated && !runtime.core.profile.simulationOnly &&
      prefs.getString("commissioned", "") == runtime.core.profile.hash.c_str();
  runtime.simulation = !runtime.hardwareReady;
  if (!storage) {
    runtime.faultActive = true;
    runtime.core.fault("storage-unavailable");
  }
  xTaskCreate(verificationTask, "verify", 12288, nullptr, 1, nullptr);
#if PROVISIONED
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  static std::string uri = std::string("mqtts://") + MQTT_HOST + ":" +
                           std::to_string(MQTT_PORT),
                     willTopic = prefix() + "availability";
  esp_mqtt_client_config_t cfg = {};
  cfg.uri = uri.c_str();
  cfg.client_id = ROBOT_ID;
  cfg.username = MQTT_USERNAME;
  cfg.password = MQTT_PASSWORD;
  cfg.cert_pem = BROKER_CA_CERT;
  cfg.lwt_topic = willTopic.c_str();
  cfg.lwt_msg = "offline";
  cfg.lwt_qos = 1;
  cfg.lwt_retain = 1;
  cfg.buffer_size = 4096;
  cfg.out_buffer_size = 4096;
  cfg.keepalive = 10;
  mqtt = esp_mqtt_client_init(&cfg);
  esp_mqtt_client_register_event(
      mqtt, static_cast<esp_mqtt_event_id_t>(ESP_EVENT_ANY_ID), mqttEvent,
      nullptr);
  esp_mqtt_client_start(mqtt);
#else
  Serial.println("Provision secrets.h, ca_cert.h and server_key.h for MQTTS. "
                 "No insecure fallback.");
#endif
}
void loop() {
  static uint64_t lastPublish = 0, lastWifi = 0, lastStep = 0;
  auto now = mono();
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      serialCommand(serialLine);
      serialLine.clear();
    } else if (c != '\r' && serialLine.size() < 256)
      serialLine += c;
  }
  Message *m = nullptr;
  while (xQueueReceive(emergencyQueue, &m, 0) == pdTRUE)
    process(m);
  if (overflow.exchange(false)) {
    runtime.core.stop(now, "message-overflow");
    runtime.invalidate();
  }
  if (xQueueReceive(normalQueue, &m, 0) == pdTRUE) {
    process(m);
    while (xQueueReceive(emergencyQueue, &m, 0) == pdTRUE)
      process(m);
  }
  now = mono();
  if (now - lastStep >= 20) {
    lastStep = now;
    if (runtime.core.state == State::CALIBRATING) {
      if (now - calibrationBeat > runtime.core.profile.heartbeatMs) {
        calibrationIndex = -1;
        runtime.core.state = State::UNCALIBRATED;
        runtime.core.reason = "calibration-timeout";
      } else if (calibrationIndex >= 0 && calibrationReference) {
        auto s = runtime.core.profile.servos[calibrationIndex];
        double vmax = std::min(2., runtime.core.profile.velocity[s.joint] *
                                       fabs(s.ratio)),
               acc = std::min(5., runtime.core.profile.acceleration[s.joint] *
                                      fabs(s.ratio)),
               d = calibrationTarget - calibrationPosition;
        double desired =
            std::copysign(std::min(vmax, sqrt(2 * acc * fabs(d))), d);
        calibrationVelocity += std::max(
            -acc * .02, std::min(acc * .02, desired - calibrationVelocity));
        double next = calibrationPosition + calibrationVelocity * .02;
        if (fabs(d) < .001) {
          next = calibrationTarget;
          calibrationVelocity = 0;
        }
        if (next >= s.min && next <= s.max) {
          calibrationPosition = next;
          double pulse = s.pulseMin + next / 180 * (s.pulseMax - s.pulseMin);
          if (pwm.setPWM(s.channel, 0, uint16_t(pulse * 4096 / 20000)) != 0) {
            runtime.core.fault("pca-write");
            calibrationIndex = -1;
          }
        }
      }
    } else {
      bool control = connected && !runtime.session.empty() &&
                     runtime.sessionExpiry > uint64_t(time(nullptr)) * 1000;
      bool changed = runtime.core.tick(now, control);
      if (!control && (runtime.core.state == State::STOPPING ||
                       runtime.core.state == State::HOLD))
        runtime.invalidate();
      if (changed && !runtime.simulation && runtime.hardwareReady) {
        auto pulses = runtime.core.profile.pulses(runtime.core.q);
        for (int i = 0; i < 8; i++)
          if (pwm.setPWM(runtime.core.profile.servos[i].channel, 0,
                         uint16_t(pulses[i] * 4096 / 20000)) != 0) {
            runtime.core.fault("pca-write");
            runtime.faultActive = true;
            break;
          }
      }
    }
  }
  if (now - lastPublish >= 500) {
    lastPublish = now;
    status();
  }
  if (now - lastWifi > 5000) {
    lastWifi = now;
    if (PROVISIONED && WiFi.status() != WL_CONNECTED)
      WiFi.reconnect();
  }
  delay(1);
}
