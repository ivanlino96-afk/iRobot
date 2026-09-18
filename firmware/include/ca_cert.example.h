#pragma once

// Copy to ca_cert.h and set the trusted root CA PEM that validates
// mqtt.3dlab.site. Use the CA/root certificate, not a private key or password.
// Do not use setInsecure() in a deployed robot.
constexpr char BROKER_CA_CERT[] = R"EOF(
-----BEGIN CERTIFICATE-----
replace-with-your-ca-certificate
-----END CERTIFICATE-----
)EOF";
