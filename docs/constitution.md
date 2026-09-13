# Constitución de AiRobot

## 1. Seguridad física primero

El firmware del ESP32-C3 es la autoridad final para autorizar movimiento. Debe rechazar órdenes fuera de límites, aplicar velocidad y aceleración configuradas, y priorizar la parada de emergencia. Ningún movimiento seguro puede depender de la disponibilidad de Internet. Ante pérdida de conexión, el robot mantiene su posición objetivo actual mediante control local.

## 2. Configuración explícita y trazable

Los límites, ceros, inversiones, offsets, geometría y mapeo PCA9685-servo son configuración versionada por robot. No se codifican como valores implícitos ni se asumen por el orden de conectores.

## 3. Separación de responsabilidades

Flutter implementa MVVM y Clean Architecture. La presentación no accede directamente a MQTT, API, cinemática ni hardware. El backend gestiona identidad, propiedad y persistencia. El firmware valida y ejecuta control local.

## 4. Comunicación segura por defecto

La comunicación remota usa MQTT sobre TLS. Un usuario solo puede operar robots vinculados a su cuenta. Los QR no contienen secretos permanentes y el acceso a tópicos se restringe por robot.

## 5. Movimientos reproducibles

Los programas se describen mediante posiciones, acciones de garra, velocidad y pausas. Las órdenes deben ser identificables, tener caducidad y ser seguras frente a duplicados. La cinemática inversa debe validar alcance antes de publicar una orden y seleccionar la solución válida más rápida que respete límites y condiciones de seguridad.

## 6. Pruebas antes de movimiento físico

La cinemática, serialización MQTT, límites, calibración, secuencias, pérdida de red y parada de emergencia se prueban antes de accionar el robot. Las pruebas físicas iniciales usan baja velocidad y límites conservadores.
