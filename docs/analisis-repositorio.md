# Análisis del repositorio iRobot

Fecha: 2026-09-13. Código revisado: `877720f`, rama `main`.

## Diagnóstico

El repositorio contiene la especificación y un prototipo inicial para controlar por Internet un brazo de seis grados de libertad más garra, con ocho servos MG995, un ESP32-C3 y un PCA9685. No contiene todavía un sistema operativo de extremo a extremo.

## Componentes y funcionamiento real

| Componente | Implementación actual |
| --- | --- |
| `app/lib/main.dart` | Interfaz Flutter con Riverpod. La pantalla TCP acepta X/Y/Z y cambia estado local. Control, programas, enseñanza y configuración son pantallas en construcción. |
| `app/pubspec.yaml` | Declara Flutter, Riverpod, GoRouter, MQTT, Dio, almacenamiento seguro y escáner QR. El código solo importa Flutter y Riverpod. |
| `firmware/src/main.cpp` | Configuración Wi-Fi/MQTTS, recepción JSON, caducidad y deduplicación básica, comandos de servo y home, y adaptación PWM. Actuadores deshabilitados por constante. |
| `firmware/platformio.ini` | Proyecto Arduino para `esp32-c3-devkitm-1`, con Adafruit PWM Servo Driver, ArduinoJson y PubSubClient. La correspondencia con la placa Mini y sus pines I2C requiere verificación. |
| `design/airobot-mobile-mock.html` | Maqueta HTML/CSS sin lógica JavaScript; no controla el robot. |
| `spec.md`, `docs/constitution.md` y plan técnico | Describen la arquitectura y funciones previstas, que exceden ampliamente lo implementado. |
| Backend, base de datos y broker | No hay implementación de API, PostgreSQL, despliegue Mosquitto ni ACL en este repositorio. |

La app arranca, crea un estado local y muestra la interfaz. Pulsar mover, home o parar solo modifica ese estado: no publica MQTT ni recibe confirmaciones.

El firmware inicializa I2C/PCA9685, intenta Wi-Fi y configura NTP. Solo intenta MQTT si existe `ca_cert.h`. Se suscribe a `airobot/v1/robots/<robotId>/command` y publica estado retenido en el sufijo `state`. Admite `moveServo` y `goHome`, rechaza `moveTcp` y responde a `emergencyStop` publicando un texto. Con `kActuatorsEnabled = false`, `moveServo` valida pero no escribe PWM.

## Hallazgos priorizados

1. **Crítico antes de habilitar hardware: la emergencia no detiene ni enclava el controlador.** En `firmware/src/main.cpp:112` únicamente se publica un estado. Una orden válida posterior sigue aceptándose. Tampoco hay entrada de parada física ni supervisor local. Implementar un estado de emergencia que bloquee órdenes, cancele trayectorias y requiera rearme explícito, con una estrategia física adecuada al brazo.
2. **Crítico antes de habilitar hardware: no existe planificación segura del movimiento.** `moveServo` escribe la meta directamente (`firmware/src/main.cpp:75`), sin velocidad, aceleración ni coordinación de los dos servos de J2. La calibración es una tabla fija de ejemplo. Mantener deshabilitados los actuadores hasta implementar y probar estos controles.
3. **Alto: la UI informa conexión y envío sin comunicación real.** `app/lib/main.dart:17` inicia conectado y las tres acciones siguientes solo cambian memoria. Separar un modo de demostración explícito y mostrar conexión/aceptación únicamente a partir de eventos reales.
4. **Alto: deduplicación insuficiente.** `firmware/src/main.cpp:114` solo recuerda la última orden. La secuencia A, B, A acepta A nuevamente si no ha caducado; reiniciar borra el historial. Definir una ventana de deduplicación y política de reinicio.
5. **Alto: contrato y autorización incompletos.** Hay usuario/contraseña MQTT y certificado CA, pero no implementación verificable de propiedad, ACL, vinculación, hora de creación ni validación completa del esquema. `servoIndex` se convierte a `uint8_t` antes de validar el rango: un entero como 256 puede convertirse en 0. Validar tipo y rango antes de estrechar el valor y probar el rechazo de entradas malformadas.
6. **Medio: home puede comunicar éxito parcial.** `firmware/src/main.cpp:118` ignora el resultado de cada `moveServo` y siempre anuncia aceptación. Una configuración futura con home inválido podría mover unos canales y rechazar otros. Validar todos los objetivos antes de ejecutar.
7. **Medio: coordenadas inválidas se sustituyen por cero.** `app/lib/main.dart:83` usa `double.tryParse(...) ?? 0`. Faltan errores de entrada, comprobación de valores finitos, alcance y límites; corregir antes de conectar este flujo al hardware.
8. **Brecha funcional:** faltan cinemática inversa, perfiles persistentes/versionados, programas, enseñanza, autenticación, QR, nube y separación Clean Architecture. Tampoco existen pruebas ni CI en los archivos clonados.

La constante de actuadores deshabilitados reduce el riesgo actual: estos defectos de control deben resolverse antes de cambiarla. Los MG995 no proporcionan posición medida; los estados deben distinguir metas de posiciones físicas.

## Aspectos útiles de la base actual

- La especificación define geometría, unidades, ejes y responsabilidades.
- Sin certificado CA, el firmware evita conectarse por MQTT en vez de degradar TLS.
- Los comandos normales requieren caducidad y reloj sincronizado.
- Los archivos locales de credenciales y certificados están excluidos de Git; los archivos versionados son ejemplos.
- Los actuadores están explícitamente deshabilitados y TCP se rechaza mientras no existe perfil calibrado.

## Orden propuesto para continuar

1. Definir protocolo versionado, respuestas y estados; implementar pruebas de límites, tipos, caducidad, duplicados y emergencia.
2. Construir configuración/calibración por canal, coordinación de J2 y movimiento interpolado con límites locales.
3. Completar la estructura Flutter y sus proyectos de plataforma; distinguir demostración de conexión real y conectar MQTT mediante repositorios y casos de uso.
4. Implementar API, identidad, propiedad, ACL del broker y persistencia.
5. Incorporar cinemática comprobable, enseñanza y ejecución de secuencias.
6. Validar integración y fallos de red antes de pruebas físicas progresivas.

## Alcance de la verificación

Se clonó el repositorio y se revisaron los archivos fuente, configuración, maqueta y especificaciones. Flutter y Dart están disponibles en PATH. PlatformIO no se encontró en PATH ni en su ubicación habitual; no existen dependencias resueltas en `app/.dart_tool`, salidas de PlatformIO ni proyectos `app/ios` o `app/android`.

No se ejecutó compilación, resolución de paquetes, pruebas automatizadas ni pruebas físicas. Por tanto, no se certifica compatibilidad de versiones, compilación, conectividad o comportamiento en hardware. Este documento registra análisis estático del código, no un resultado de ejecución. No se modificó el programa.
