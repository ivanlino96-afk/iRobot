#pragma once

// Copy to ca_cert.h and set the PEM certificate chain for the MQTT broker.
// Do not use setInsecure() in a deployed robot.
constexpr char BROKER_CA_CERT[] = R"EOF(
-----BEGIN CERTIFICATE-----
replace-with-your-ca-certificate
-----END CERTIFICATE-----
)EOF";
