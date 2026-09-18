#pragma once

// Copy to secrets.h and fill with deployment values. Never commit secrets.h.
// The ESP32 authenticates to MQTT as this robot; Flutter receives separate,
// short-lived credentials from the backend. Do not use a Flutter test account.
constexpr char WIFI_SSID[] = "replace-me";
constexpr char WIFI_PASSWORD[] = "replace-me";
constexpr char MQTT_HOST[] = "mqtt.3dlab.site";
// Traefik terminates TLS for MQTT on the already secured HTTPS entry point.
constexpr uint16_t MQTT_PORT = 443;
constexpr char ROBOT_ID[] = "AR-001";
constexpr char MQTT_USERNAME[] = "robot-AR-001";
constexpr char MQTT_PASSWORD[] = "replace-me";
