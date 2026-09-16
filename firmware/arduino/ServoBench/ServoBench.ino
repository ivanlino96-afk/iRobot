#include <Adafruit_PWMServoDriver.h>
#include <Wire.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// Control directo por USB: XIAO ESP32-C3 + PCA9685 + MG995 posicionales.
constexpr int SDA_PIN = 8, SCL_PIN = 9;
constexpr uint8_t PCA_ADDRESS = 0x40;
// Cuentas PWM a 50 Hz, conservadas del programa original del usuario.
// No son microsegundos ni extremos calibrados automaticamente.
constexpr uint16_t SERVOMIN = 150, SERVOMAX = 600;
Adafruit_PWMServoDriver pca(PCA_ADDRESS);
int selected = 0; // 1 representa siempre el par 1+2; canal 2 es alias.
bool healthy = false, greeted = false;
bool hasCommand[8] = {};
float lastCommand[8] = {};
char line[80];
size_t used = 0;
bool overflow = false;

void showSelection() {
  if (selected == 1)
    Serial.println("Seleccionado: par canales 1 y 2 en espejo.");
  else
    Serial.printf("Seleccionado: canal %d.\n", selected);
}
void help() {
  Serial.println("\n--- MG995: control directo por angulo ---");
  Serial.println("canal N : selecciona 0..7; 1 y 2 seleccionan el mismo par");
  Serial.println("90      : envia 90 grados; tambien puedes escribir mover 90");
  Serial.println("estado  : muestra las ultimas consignas enviadas");
  Serial.println("apagar  : apaga los pulsos de TODOS los canales");
  Serial.println("i2c     : busca dispositivos (probar sin carga)");
  Serial.println("ayuda   : muestra estos comandos");
  Serial.println(
      "Sin interpolacion ni espera: cada angulo sustituye la orden anterior.");
  Serial.println("No se mide posicion ni avance fisico del servo.");
  showSelection();
  Serial.printf("PCA9685: %s | SDA GPIO8, SCL GPIO9 | 50 Hz\n",
                healthy ? "OK" : "ERROR I2C");
}
void fault() {
  healthy = false;
  Serial.println(
      "ERROR I2C: no se confirma la escritura. Revisa conexiones y reinicia.");
}
bool writeServo(int channel, float angle) {
  const uint16_t pulse =
      lroundf(SERVOMIN + angle / 180.0f * (SERVOMAX - SERVOMIN));
  if (pca.setPWM(channel, 0, pulse) != 0) {
    fault();
    return false;
  }
  if (hasCommand[channel]) {
    Serial.printf("Canal %d: consigna %.1f -> %.1f grados | PWM %u\n", channel,
                  lastCommand[channel], angle, pulse);
  } else {
    Serial.printf("Canal %d: primera consigna %.1f grados | PWM %u\n", channel,
                  angle, pulse);
  }
  lastCommand[channel] = angle;
  hasCommand[channel] = true;
  return true;
}
void moveTo(float angle) {
  if (!healthy) {
    Serial.println(
        "ERROR: PCA9685 no disponible. Ejecuta i2c y revisa cableado.");
    return;
  }
  if (!isfinite(angle) || angle < 0 || angle > 180) {
    Serial.println("ERROR: escribe un angulo entre 0 y 180.");
    return;
  }
  showSelection();
  if (selected == 1) {
    if (!writeServo(1, angle))
      return;
    if (!writeServo(2, 180.0f - angle)) {
      Serial.println("ERROR: el canal 1 recibio la orden; el par puede quedar "
                     "descoordinado.");
      return;
    }
  } else if (!writeServo(selected, angle))
    return;
  Serial.println(
      "Orden enviada. Posicion fisica no medida. Puedes enviar otro angulo.");
}
void status() {
  showSelection();
  for (int i = 0; i < 8; ++i) {
    if (hasCommand[i])
      Serial.printf("Canal %d: ultima consigna %.1f grados\n", i,
                    lastCommand[i]);
    else
      Serial.printf("Canal %d: sin consigna activa conocida\n", i);
  }
}
void scanI2c() {
  int found = 0;
  Serial.println("Escaneando SDA GPIO8 / SCL GPIO9; esperado 0x40.");
  for (uint8_t address = 8; address < 120; ++address) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      Serial.printf("Responde 0x%02X\n", address);
      ++found;
    }
  }
  if (!found)
    Serial.println("Sin respuesta: revisar VCC 3.3V, GND comun, SDA y SCL.");
}
bool parseNumber(const char *text, float &value) {
  if (!text || !*text)
    return false;
  char *end;
  value = strtof(text, &end);
  return end != text && *end == '\0' && isfinite(value);
}
void command(char *input) {
  char *context = nullptr;
  char *cmd = strtok_r(input, " \t", &context);
  if (!cmd)
    return;
  char *arg = strtok_r(nullptr, " \t", &context);
  if (strtok_r(nullptr, " \t", &context)) {
    Serial.println("ERROR: demasiados argumentos.");
    return;
  }
  if (!arg && !strcmp(cmd, "ayuda")) {
    help();
    return;
  }
  if (!arg && !strcmp(cmd, "estado")) {
    status();
    return;
  }
  if (!arg && !strcmp(cmd, "i2c")) {
    scanI2c();
    return;
  }
  if (!arg && !strcmp(cmd, "apagar")) {
    if (!healthy) {
      Serial.println("ERROR I2C: no se puede confirmar apagado.");
      return;
    }
    for (int i = 0; i < 16; ++i) {
      if (pca.setPWM(i, 0, 4096) != 0) {
        fault();
        return;
      }
      if (i < 8)
        hasCommand[i] = false;
    }
    Serial.println("Pulsos apagados en todos los canales.");
    return;
  }
  float value;
  if (arg && !strcmp(cmd, "canal")) {
    if (!parseNumber(arg, value) || value < 0 || value > 7 ||
        floorf(value) != value) {
      Serial.println("ERROR: canal entero de 0 a 7.");
      return;
    }
    selected = value == 2 ? 1 : (int)value;
    showSelection();
    Serial.println(
        "Escribe el angulo (0..180). Los otros canales conservan sus pulsos.");
    return;
  }
  if ((!arg && parseNumber(cmd, value)) ||
      (arg && !strcmp(cmd, "mover") && parseNumber(arg, value))) {
    moveTo(value);
    return;
  }
  Serial.println("ERROR: usa canal N, un angulo, estado, apagar, i2c o ayuda.");
}
void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);
  Wire.setTimeOut(10);
  healthy = pca.begin();
  if (healthy) {
    pca.setPWMFreq(50);
    for (int i = 0; i < 16; ++i) {
      if (pca.setPWM(i, 0, 4096) != 0) {
        fault();
        break;
      }
    }
  }
}
void loop() {
  if (!Serial)
    greeted = false;
  if (Serial && !greeted) {
    help();
    greeted = true;
  }
  for (int budget = 0; budget < 80 && Serial.available(); ++budget) {
    const char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (overflow)
        Serial.println("ERROR: linea demasiado larga; descartada.");
      else {
        line[used] = '\0';
        command(line);
      }
      used = 0;
      overflow = false;
    } else if (!overflow && used < sizeof(line) - 1)
      line[used++] = c;
    else
      overflow = true;
  }
}
