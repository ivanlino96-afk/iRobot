# Instalación y prueba

## Alcance actual

La primera comprobación de la app confirma una respuesta del ESP32 mediante MQTT. El indicador muestra Conectando…, ESP32 conectado o Error de conexión. La conexión no requiere calibración ni programas y no mueve servos. La pérdida de telemetría durante tres segundos invalida la conexión. Simulador tiene una etiqueta propia.

No se comprueba propiedad por robot. Se conserva autenticación general del servicio y exclusividad temporal de control para evitar órdenes simultáneas. El QR no es requisito para acceder a un robot registrado. No se incluye botón físico ni circuito de corte.

## 1. Backend local

Requisitos: Docker en ejecución, Node.js y npm, Python 3, OpenSSL y compilador C++17. Desde la raíz:

```sh
npm ci --prefix backend
python3 deployment/setup.py localhost
docker compose --env-file deployment/.env -f deployment/compose.yaml up -d --build
```

Ejecutar setup solo en instalaciones nuevas: rechaza sobrescribir las claves existentes. En este equipo ya se ejecutó. El entorno local expone HTTPS en localhost:18443, MQTT TLS en localhost:18883 y PostgreSQL en localhost:55432. Los archivos deployment/private y deployment/.env contienen secretos y se excluyen de Git.

Este compose escucha solo en localhost. Para un teléfono o ESP32 físico se necesita configurar un nombre accesible desde su red, certificados válidos para ese nombre y publicar los puertos HTTPS/MQTTS correspondientes. localhost desde un teléfono identifica al teléfono, no al servidor. No desactivar la comprobación TLS. La VPS todavía requiere esta configuración de red y certificados.

## 2. Registrar el controlador

El CLI backend/src/provision.js recibe ROBOT_ID y un directorio privado de salida, con DATABASE_URL, MQTT_URL, MQTT_CA y credenciales administrativas MQTT en el entorno. Genera device.json y pairing.json. El QR es opcional para esta etapa; el registro del dispositivo sigue siendo necesario para disponer de sus credenciales de transporte. No copiar credenciales administrativas al firmware ni a la app.

## 3. Firmware

Instalar PlatformIO y ejecutar desde firmware:

```sh
pio run -e xiao_esp32c3
```

Copiar include/secrets.example.h a include/secrets.h y completar Wi-Fi, ID y credenciales MQTT del dispositivo. Crear ca_cert.h y server_key.h a partir de sus ejemplos: CA del broker y clave pública de firma del backend, respectivamente. La clave privada de firma queda en el servidor.

Compilar otra vez y cargar por USB:

```sh
pio run -e xiao_esp32c3 -t upload
pio device monitor
```

La placa es Seeed Studio XIAO ESP32-C3; I2C usa GPIO6/SDA y GPIO7/SCL. No cargar el entorno network_compile_check: contiene datos ficticios y solo comprueba compilación. Para comprobar conexión inicialmente no hace falta habilitar servos.

## 4. Aplicación

Desde app, con Flutter instalado:

```sh
flutter pub get
flutter run
```

En iOS se necesita Xcode; el módulo nativo utiliza CocoaPods. Abrir Conectar, configurar la URL HTTPS e iniciar sesión general. Seleccionar el ID registrado: no se exige vincularlo a un propietario. Debe aparecer ESP32 conectado solo tras recibir la confirmación del controlador. Si falla, se muestra Error de conexión y el detalle de la operación. Verificar servidor, certificado, Wi-Fi y alimentación del ESP32. No confundir Usar simulador con una conexión física.

## 5. Pruebas automáticas

Desde la raíz, tras instalar las dependencias PlatformIO del firmware:

```sh
sh tools/test-core.sh
npm test --prefix backend
sh tools/build-simulator.sh
node tools/test-integration.mjs
```

La última prueba requiere el compose local activo y ejecuta HTTPS, PostgreSQL, MQTT TLS y el Runtime C++ simulado. Comprueba movimiento, bloqueo, recuperación y pérdida de heartbeat. No activa hardware.

Desde app:

```sh
flutter analyze
flutter test test/widget_test.dart
```

## 6. Prueba inicial del ESP32

1. Encender el ESP32 con firmware y credenciales configurados; mantener los servos deshabilitados.
2. Seleccionar el robot en la app y comprobar el indicador de éxito.
3. Desconectar la red o apagar el ESP32: verificar que desaparece el éxito y aparece error de conexión.
4. Intentar conectar estando apagado: no debe aparecer éxito por estar disponible únicamente el servidor.
5. Restablecer la red y reconectar: debe confirmar el nuevo arranque sin habilitar movimiento automáticamente.
6. Acceder desde otra cuenta: el robot debe ser visible sin validación de propietario. Una sesión de control ocupada debe informar conflicto.

## 7. Pruebas físicas posteriores

Aún se necesita medir y validar la correspondencia de los ocho servos con los canales PCA9685, sus límites, offsets, sentidos y la geometría de los ejes. El perfil de simulación no es una calibración del brazo real. Alimentar servos mediante fuente externa y masa común, nunca desde el ESP32.

Antes de movimiento conjunto, probar cada servo lentamente, con límites conservadores, y calibrar por separado los dos de J2. Después confirmar referencia, habilitar explícitamente, comprobar home, desplazamientos pequeños, secuencia corta, parada software y pérdida de red. Registrar resultados reales antes de considerar validada la instalación física.
