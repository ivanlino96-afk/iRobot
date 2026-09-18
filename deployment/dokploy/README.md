# AiRobot en Dokploy

Configuración preparada; pendiente de completar dominio, certificados y acceso a la VPS. No ejecutar deployment/setup.py para este despliegue: ese script configura exclusivamente el entorno local.

## Servicios y dominios

- api.example.com: registro DNS A hacia la VPS. En Dokploy, Domains: servicio `api`, puerto de contenedor `8080`, HTTPS y certificado Let's Encrypt.
- mqtt.3dlab.site: ya usa el listener TLS de Traefik en el puerto 443. El broker
  no publica un puerto de host; el enrutamiento TCP se define en
  `mqtt-traefik.yml`.
- PostgreSQL permanece accesible exclusivamente dentro de la red del compose.

Los nombres anteriores son ejemplos. La red interna asigna al broker un alias igual a MQTT_PUBLIC_HOST; así la API comprueba el mismo nombre del certificado sin salir a Internet para comunicarse con Mosquitto.

## Archivos persistentes de la VPS

Preparar un directorio exclusivo, por ejemplo `/opt/airobot/private`, fuera del checkout gestionado por Dokploy:

```text
private/
  api/signing.pem                 # clave privada RSA del backend
  signing.pub                    # clave pública para el firmware
  mqtt/ca.crt                    # CA o conjunto de CA que valida al broker
  mqtt/ca.crt                    # CA que valida mqtt.3dlab.site para la API
  broker/dynamic-security.json   # base de credenciales de Mosquitto
  provision/                     # credenciales de dispositivo, solo para el operador
```

Traefik emite y renueva el certificado público para `mqtt.3dlab.site`. Copiar
`mqtt-traefik.yml` al directorio dinámico de Traefik después de desplegar el
broker. La API y el firmware validan la CA pública correspondiente. No usar los
certificados ficticios de firmware/test/build-config.

La API corre con UID 1000 y necesita leer `api/signing.pem` y escribir en
`provision/`. Mosquitto corre con UID 1883 y necesita escribir en `broker/`.
Usar directorios privados y permisos de lectura limitados, no chmod 777. La
clave pública y la CA son los únicos archivos criptográficos que se copian al
firmware; nunca la clave privada RSA ni las credenciales administrativas MQTT.

Generar una clave RSA de 2048 bits o superior con OpenSSL, y tres secretos aleatorios distintos para PostgreSQL, autenticación y administración MQTT. Guardar la contraseña PostgreSQL en hexadecimal para que sea válida dentro de DATABASE_URL. Inicializar dynamic-security.json con `mosquitto_ctrl dynsec init` de la misma imagen eclipse-mosquitto:2.0.22 y el usuario `admin`; su contraseña debe coincidir con MQTT_ADMIN_PASSWORD. No reinicializar este archivo al redesplegar: contiene las credenciales de los dispositivos.

## Configuración del panel

1. Crear proyecto AiRobot y servicio Docker Compose.
2. Conectar el repositorio que contenga estos cambios. Ruta Compose: `deployment/dokploy/compose.yaml`; contexto de compilación relativo definido en el archivo.
3. Completar Environment tomando `env.example` como referencia. AIROBOT_PRIVATE_DIR es una ruta absoluta de la VPS, no del Mac.
4. Preparar certificados, firma y credenciales en la VPS antes de desplegar.
5. Añadir el dominio HTTPS para el servicio `api`, puerto 8080. Revisar Preview Compose y comprobar que la API conserva las redes `internal` y `dokploy-network`.
6. Copiar `mqtt-traefik.yml` a `/etc/dokploy/traefik/dynamic/mqtt.yml`. Mantener
   80/443 según la instalación existente de Dokploy. No publicar 1883, 5432 ni
   8080.
7. Desplegar y revisar logs de postgres, broker y api. Debe aparecer `AiRobot API ready`.

## Verificación

```sh
curl --fail https://api.example.com/health
openssl s_client -connect mqtt.3dlab.site:443 -servername mqtt.3dlab.site -verify_return_error </dev/null
```

La primera comprobación debe devolver `{"ok":true}`. La segunda debe verificar correctamente la cadena TLS. `/health` indica disponibilidad HTTP; la prueba de conexión de la app es la que confirma la respuesta del ESP32.

Después registrar el robot mediante el CLI `backend/src/provision.js` en el entorno del backend y guardar la salida en un directorio privado. Configurar el firmware con Wi-Fi, ID, credenciales del dispositivo, CA y clave pública RSA. La app usa la URL HTTPS de la API; obtiene el endpoint MQTT del backend. La primera prueba física se realiza con los servos deshabilitados.

## Operación

Respaldar la base PostgreSQL, el directorio broker y las claves del servicio mediante almacenamiento privado. Mantener estos datos al actualizar los contenedores. Renovar el certificado MQTT antes de su vencimiento y recargar Mosquitto; comprobar nuevamente TLS y reconexión del dispositivo. El mecanismo concreto de emisión/renovación depende del proveedor DNS y se configura cuando se conozca el dominio.

El acceso por propietario está desactivado por decisión del usuario; se mantiene autenticación general del servicio y sesión exclusiva de control.

Referencia oficial: https://docs.dokploy.com/docs/core/docker-compose/domains
