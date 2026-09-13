# Especificación funcional — AiRobot

## Propósito

Controlar un brazo robótico de 6 grados de libertad y garra desde una aplicación Flutter para iOS, tanto dentro como fuera de la red local.

## Hardware

- ESP32-C3 Mini.
- PCA9685 conectado por I2C.
- Ocho servos MG995.
- Fuente externa de 5–6 V para servos y tierra común con el controlador.

## Modelo mecánico inicial

El TCP es el centro de contacto entre las mordazas de la garra. Todas las longitudes se expresan en milímetros. La posición home, definida durante la configuración desde la aplicación, establece la referencia X=0, Y=0, Z=0.

| Tramo | Longitud |
| --- | ---: |
| J1 a J2 | 80 |
| J2 a J3 | 120 |
| J3 a J4 | 70 |
| J4 a J5 | 80 |
| J5 a J6 | 80 |
| J6 a TCP | 140 |

| Eje | Función |
| --- | --- |
| J1 | Rotación de base |
| J2 | Inclinación del primer brazo con dos servos coordinados |
| J3 | Inclinación del segundo brazo |
| J4 | Inclinación adelante/atrás |
| J5 | Inclinación derecha/izquierda |
| J6 | Orientación del gripper |
| J7 | Apertura/cierre de garra |

La correspondencia entre cada servo físico y canal PCA9685 se configura y calibra por robot.

## Funcionalidades MVP

1. Control manual individual de cada servo.
2. Movimiento cartesiano del TCP a una posición X/Y/Z en milímetros.
3. Rechazo de posiciones fuera de alcance o que excedan límites configurados.
4. Selección de la combinación articular válida más rápida que respete condiciones de seguridad para llegar a un destino X/Y/Z.
5. Modo de enseñanza que guarda movimientos ordenados desde la aplicación.
6. Creación, edición, guardado por nombre y ejecución de programas secuenciales.
7. Cada paso programado puede incluir punto X/Y/Z, velocidad, pausa y acción de garra.
8. Pantalla de configuración para geometría, límites, cero, inversión, offsets y relación de los dos servos de J2.
9. Posición home, estado de conexión y parada de emergencia.
10. Inicio de sesión y vinculación de un robot a una única cuenta mediante QR de un solo uso.
11. Persistencia en nube de perfiles, secuencias y propiedad del robot.

## Arquitectura

- Aplicación: Flutter/Dart, MVVM y Clean Architecture.
- Firmware: C++ para ESP32-C3; control local del PCA9685 y validación de seguridad.
- Backend: API en la VPS con base de datos PostgreSQL.
- Autenticación: proveedor de identidad compatible con Flutter.
- Mensajería: Mosquitto MQTT sobre TLS, con permisos por robot.

## Mensajería

Cada robot expone tópicos aislados para comandos, estado, configuración, telemetría y emergencia. Las órdenes contienen al menos identificador, hora de creación y datos para rechazar duplicados o mensajes vencidos.

## Restricciones

- La aplicación no genera firmware para cada modificación de configuración.
- El firmware valida todas las órdenes recibidas, incluso si provienen de una aplicación autorizada.
- El modo de enseñanza no obtiene posiciones moviendo físicamente el brazo a mano, porque los MG995 no proporcionan realimentación de posición.
- Ante pérdida de conectividad, el ESP32 mantiene localmente la posición objetivo actual.
