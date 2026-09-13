# Constitución de AiRobot

## 1. Seguridad física primero

El firmware del ESP32-C3 es la autoridad final de software para autorizar movimiento. Debe rechazar órdenes fuera de límites, aplicar velocidad y aceleración configuradas y priorizar una parada de software enclavada. Por decisión del propietario, esta etapa no incluye pulsador físico ni circuito de corte de alimentación (D-02); su ausencia no bloquea el alcance actual. La parada prioritaria cancela la ejecución, deja de avanzar consignas y bloquea nuevas órdenes. El rearme se solicita explícitamente desde la app autenticada y lo valida el firmware; nunca inicia movimiento. El arranque tampoco inicia ni reanuda movimientos. Para este modelo pequeño, el propietario acepta la caída del brazo al perder energía (D-01).

La parada remota requiere comunicación y firmware operativo. No corta energía ni garantiza detención física ante bloqueo del controlador o fallo del driver. La protección ante pérdida de red se ejecuta localmente mediante supervisión de sesión. La interfaz identifica esta función como parada por software.

Ante pérdida de comunicación de control, se cancela el programa, se ejecuta una parada controlada local dentro de los límites del perfil y se mantiene la última consigna de esa parada. No se continúa hacia el destino remoto ni se reanuda al reconectar. Esta retención describe una consigna, no una garantía de posición física.

## 2. Configuración explícita y trazable

Los límites, ceros, inversiones, offsets, geometría y mapeo PCA9685-servo son configuración versionada por robot. No se codifican como valores implícitos ni se asumen por el orden de conectores. Órdenes y programas identifican la versión y hash del perfil; cualquier discrepancia impide ejecutar. Cambiar home o calibración invalida la validación previa de programas. J2 se controla como una articulación coordinada; el movimiento independiente de sus servos se restringe a un procedimiento local de calibración con soporte mecánico y límites previamente validados.

## 3. Separación de responsabilidades

Flutter implementa MVVM y Clean Architecture. La presentación no accede directamente a MQTT, API, cinemática ni hardware. El backend gestiona identidad, propiedad y persistencia. El firmware valida y ejecuta control local.

## 4. Comunicación segura por defecto

La comunicación remota usa MQTT sobre TLS. Un usuario solo puede operar robots vinculados a su cuenta. Los QR no contienen secretos permanentes y el acceso a tópicos se restringe por robot.

## 5. Movimientos reproducibles

Los programas se describen mediante posiciones, acciones de garra, velocidad y pausas. Las órdenes deben ser identificables, tener caducidad y ser seguras frente a duplicados y reinicios. La app calcula candidatos antes de publicar y el firmware recalcula y valida la trayectoria con el mismo perfil y versión del algoritmo antes de ejecutar. Se selecciona determinísticamente el menor tiempo estimado entre candidatos válidos, sin afirmar optimalidad global ni tiempo físico medido. Sin geometría, calibración y límites de trayectoria validados no se habilita movimiento cartesiano. Las posiciones publicadas son consignas o estimaciones identificadas como tales, nunca posiciones medidas por los MG995.

## 6. Pruebas antes de movimiento físico

La cinemática, serialización MQTT, límites, calibración, secuencias, pérdida de red y parada de emergencia se prueban antes de accionar el robot. Las pruebas físicas iniciales usan baja velocidad y límites conservadores.

## 7. Jerarquía y decisiones pendientes

Esta constitución fija invariantes; `spec.md` define comportamiento y aceptación, y `specs/001-airobot-master-control/plan.md` organiza contratos, entregas y pruebas. Las decisiones físicas pendientes se registran explícitamente y bloquean solo las funciones afectadas. Los cambios documentales describen requisitos por implementar, no certifican que el código actual los cumpla.
