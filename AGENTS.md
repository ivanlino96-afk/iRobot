# AiRobot — Instrucciones para agentes

## Alcance del producto

AiRobot controla por Internet un brazo robótico de 6 grados de libertad con garra:

- Controlador: ESP32-C3 Mini.
- Driver de servos: PCA9685 por I2C.
- Actuadores: 8 servos MG995.
- Cliente: Flutter para iOS, siguiendo MVVM y Clean Architecture.
- Comunicación: MQTT seguro sobre TLS contra un broker Mosquitto alojado en una VPS.
- Persistencia cloud: perfiles del robot, propiedad, configuración y secuencias.

El producto permite control individual de servos, movimiento cartesiano del TCP en X/Y/Z, enseñanza mediante controles de la app y programas secuenciales guardados.

## Mecánica de referencia

Usar milímetros internamente. El TCP es el centro de contacto entre las mordazas de la garra. La posición home configurada desde la app establece X=0, Y=0, Z=0.

| Tramo | Longitud |
| --- | ---: |
| J1 a J2 | 80 mm |
| J2 a J3 | 120 mm |
| J3 a J4 | 70 mm |
| J4 a J5 | 80 mm |
| J5 a J6 | 80 mm |
| J6 a TCP | 140 mm |

Ejes lógicos:

- J1: rotación de base.
- J2: inclinación del primer brazo, accionada por dos servos coordinados.
- J3: inclinación del segundo brazo.
- J4: inclinación adelante/atrás.
- J5: inclinación derecha/izquierda.
- J6: orientación de la garra.
- J7: apertura/cierre de la garra.

La correspondencia física PCA9685 ↔ servo debe permanecer configurable y validarse en calibración; no asumirla desde el orden de los conectores.

## Reglas de seguridad obligatorias

- El ESP32 es la autoridad final de seguridad: toda orden recibida debe validar límites, estado y propiedad antes de mover el robot.
- Nunca ejecutar una orden que exceda límites articulares, velocidad o aceleración configurados.
- Implementar parada de emergencia con la máxima prioridad; no depender de Internet para detener el robot.
- Ante pérdida de conexión, mantener localmente la posición objetivo actual.
- Los servos 2 y 3 de J2 requieren offsets, sentido de giro y límites independientes; no moverlos hasta calibrarlos.
- No afirmar posiciones físicas reales sin calibración: los MG995 no proporcionan realimentación de posición.
- Usar una fuente externa adecuada para los servos y masa común con el controlador. No alimentar servos desde el ESP32.

## Arquitectura de software

### Flutter

- Aplicar Clean Architecture: `presentation`, `domain`, `data` e `infrastructure` separados.
- Usar MVVM: las vistas no contienen lógica de negocio ni acceso directo a MQTT/API.
- Los casos de uso del dominio incluyen: movimiento manual, movimiento cartesiano, calibración, guardar/ejecutar secuencia, emparejar robot y parada de emergencia.
- La cinemática inversa debe ser determinista, comprobable, rechazar destinos fuera de alcance y elegir la solución válida más rápida que respete condiciones de seguridad.
- La configuración mecánica es un perfil versionado, editable desde la app y sincronizado con el robot.

### Backend y comunicación

- No incluir secretos MQTT permanentes en la aplicación ni en códigos QR.
- El QR contiene un ID de robot y token aleatorio de un solo uso; el backend vincula el robot a una única cuenta.
- El backend valida identidad y propiedad antes de autorizar acceso a tópicos MQTT del robot.
- Separar tópicos por robot para comandos, estado, configuración, telemetría y emergencia.
- Usar MQTTS, autenticación, ACL por robot, QoS apropiado y mensajes de disponibilidad.
- Cada orden debe incluir `commandId`, hora de creación y datos suficientes para detectar duplicados o mensajes vencidos.

### Firmware

- Mantener firmware estable y configurable; no generar ni reflashear firmware por ajustes mecánicos.
- Recibir metas seguras y ejecutar interpolación/suavizado localmente.
- Publicar estado de conexión, ejecución, error y posición objetivo conocida.
- El firmware vuelve a validar toda orden procedente de MQTT, incluso si la app ya la validó.

## Pruebas mínimas

- Pruebas unitarias de cinemática inversa, alcance, límites, inversiones y offsets.
- Pruebas de serialización MQTT, autenticación, ACL y rechazo de comandos duplicados o vencidos.
- Pruebas de ejecución de secuencias, interrupción por emergencia y pérdida de red.
- Antes de cualquier prueba física, probar cada servo a baja velocidad y con límites conservadores.

## Convenciones

- Coordenadas: X/Y/Z y longitudes en milímetros; documentar el origen del sistema de referencia.
- Nombrar articulaciones como `J1` a `J7`; nombrar canales físicos como `pcaChannel`.
- Guardar programas como puntos cartesianos, acciones de garra, velocidad y pausas; conservar ángulos calculados solo como referencia de auditoría.
- No mezclar lógica de UI con protocolos, cinemática o control de hardware.

## Graphify

Cuando el usuario escriba `/graphify`, usar las instrucciones del skill `graphify` antes de realizar cualquier otra acción.
