# Especificación funcional — AiRobot

## Propósito

Controlar un brazo robótico de 6 grados de libertad y garra desde una aplicación Flutter para iOS, tanto dentro como fuera de la red local.

## Hardware

- Seeed Studio XIAO ESP32-C3.
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

1. Control manual de J1–J7; J2 mueve sus dos servos coordinadamente. El control individual de canales físicos se limita a calibración local supervisada.
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
- Ante pérdida de comunicación de control, el ESP32 cancela el programa y realiza una parada controlada local; mantiene la consigna final de esa parada, sin continuar hacia el destino ni reanudar al reconectar.

## Decisiones operativas del MVP

Estas reglas son requisitos de implementación. El prototipo actual no las implementa todavía.

### Estados y prioridad

La conectividad es un atributo independiente del estado de movimiento. Prioridad: parada prioritaria por software, fallo local, parada por pérdida de control, parada del operador y movimiento normal. Solo se permite una ejecución activa; órdenes de movimiento concurrentes se rechazan como `busy`, sin cola implícita.

| Estado | Comportamiento y salida |
| --- | --- |
| `BOOT_LOCKED` | Arranque sin movimiento automático. Requiere perfil válido, comprobaciones locales, referencia confirmada y habilitación explícita desde la app. No se asume que el brazo sigue en su posición anterior. |
| `UNCALIBRATED` | Bloquea operación normal. Solo permite entrar localmente al procedimiento de calibración autorizado. |
| `CALIBRATING` | Ajustes limitados y supervisados; no admite programas ni TCP. La emergencia conserva prioridad. |
| `READY` | Acepta una orden válida si perfil, referencia y autorización siguen vigentes. |
| `EXECUTING` | Ejecuta localmente una trayectoria o programa validado. Al completar pasa a `READY`. |
| `STOPPING` | Rechaza movimientos nuevos y desacelera con el perfil de parada validado. Al completar pasa a `HOLD`. Si no puede garantizar esa trayectoria, pasa a `FAULT` y aplica el bloqueo de software descrito abajo. |
| `HOLD` | Mantiene consigna de parada y conserva causa. Requiere reconocimiento explícito con control restablecido para pasar a `READY`; hace falta una nueva orden para mover. |
| `FAULT` | Cancela ejecución y bloquea nuevas consignas. Requiere eliminar causa y rearme explícito autenticado validado por firmware; vuelve a `BOOT_LOCKED`. Si el hardware no responde, informa salida desconocida. |
| `ESTOP_LATCHED` | Nombre interno del enclavamiento de software: cancela programa y cola y congela la última consigna emitida. Recuperar red no rearma. El rearme autenticado validado por firmware vuelve a `BOOT_LOCKED`; no mueve a home. No implica corte eléctrico. |

Desde cualquier estado se puede entrar en `ESTOP_LATCHED`. Reiniciar no permite eludir el enclavamiento: el arranque siempre está bloqueado, conserva el registro de enclavamiento y exige rearme si estaba activo. Un fallo de almacenamiento bloquea la habilitación. Los eventos normales no pueden borrar emergencia o fallo.

La app ofrece `Parar` como parada controlada (`STOPPING`) y `Bloquear movimiento` como solicitud prioritaria de enclavamiento por software (`ESTOP_LATCHED`). Muestra por separado solicitud enviada y confirmación del robot. Sin confirmación no afirma que se haya detenido.

D-01 resuelta: el propietario acepta la caída de este modelo pequeño al perder alimentación. D-02 resuelta para esta etapa: no se instala pulsador físico ni circuito de corte. Se elimina el requisito de corte eléctrico ante emergencia o fallo. En enclavamiento, el firmware cancela la trayectoria sin seguir interpolando hacia la meta y mantiene la última consigna emitida; los servos siguen alimentados y podrían terminar su respuesta a esa consigna. No se afirma una detención física instantánea. En FAULT se bloquean escrituras nuevas; si se pierde control de las salidas, su estado se considera desconocido. No hay respaldo independiente ante bloqueo del ESP32 o fallo del driver.

La pérdida de red conserva la política de parada controlada y HOLD mediante el supervisor local. Si falla esa parada, se entra en FAULT con las limitaciones anteriores. El enclavamiento tiene prioridad sobre STOPPING.

`resetLatch` es una orden explícita de la cuenta propietaria con autorización vigente, bootId, identificador del enclavamiento y nonce de rearme de un solo uso emitido por el firmware. Se verifica caducidad, deduplicación, ausencia de fallo activo y referencia de estado. Puede abrirse una sesión autenticada de recuperación sin permiso de movimiento para evitar depender de READY. El firmware pasa únicamente a BOOT_LOCKED, invalida la sesión anterior y el nonce; habilitar y mover requieren acciones nuevas separadas. Un mensaje retenido, repetido o dirigido a otro enclavamiento nunca rearma. La app no modifica el estado confirmado por su cuenta.

### Pérdida de control y recuperación

Toda ejecución del MVP, incluidos programas descargados, requiere una sesión de control vigente y heartbeat autenticado. Pérdida de Wi-Fi/MQTT, vencimiento del heartbeat, de la sesión o de la autorización provoca `STOPPING`; no se termina el paso ni se avanza al siguiente. En reposo provoca `HOLD`. Se invalida la sesión y cualquier orden pendiente. Los plazos de detección y parada forman parte del perfil validado: sin valores aprobados en pruebas no se habilita movimiento.

Reconectar solo recupera comunicación y telemetría. El operador debe reconocer el motivo, obtener una sesión nueva y enviar una orden nueva después de volver a `READY`. El programa cancelado conserva su registro, pero no se reanuda desde un punto intermedio. Una pérdida de energía obliga a reconfirmar la referencia mediante un procedimiento local; nunca ejecuta home automáticamente.

### Coordenadas, orientación y trayectoria

- Sistema derecho fijo a la base: +X hacia el frente de referencia, +Y hacia la izquierda mirando hacia ese frente y +Z arriba. La identificación física del frente se registra durante calibración.
- Home traslada el origen al TCP de la postura home sin girar los ejes de la base. Se conserva la transformación base→origen de trabajo en el perfil.
- Unidades: longitudes en mm, articulaciones en grados, tiempo en ms. El perfil documenta ejes, transformaciones rígidas y postura cero; las longitudes por sí solas no habilitan cinemática.
- Para TCP del MVP se mantiene la orientación de garra registrada en home, expresada como cuaternión normalizado respecto a la base. Se rechaza un destino si no admite esa orientación. No se promete control libre de orientación en este MVP.
- El movimiento es punto a punto con interpolación articular sincronizada; no promete una línea recta del TCP. La validación cubre toda la trayectoria y su parada, límites, coordinación de J2 y zonas excluidas del modelo. No se presupone detección de obstáculos externos.
- `speedPercent` es un entero de 1 a 100 que escala velocidades máximas articulares calibradas; no representa mm/s. La aceleración nunca supera el perfil, tampoco al parar. Pausas son enteros no negativos en ms. Los rangos máximos de pausas y tamaño de programas pertenecen al contrato versionado.
- El algoritmo compara tiempo planificado, después desplazamiento articular normalizado y finalmente orden lexicográfico J1–J6 para desempatar. Usa un conjunto determinista de candidatos y tolerancias numéricas versionadas. Se valida primero; se optimiza solo entre candidatos válidos.
- La telemetría publica `targetJointDegrees`, `estimatedTcpMm` y `positionSource: commanded`, junto con validez de referencia. Completar significa completar consignas, no verificar llegada física.

### Calibración y programas

J2 acepta un único objetivo lógico y transforma ambos servos con límites, inversiones y offsets independientes. Se valida el par antes de escribir cualquiera de sus salidas. Sin calibración del par se bloquea su movimiento. El procedimiento inicial de calibración requiere límites provisionales conservadores y soporte físico confirmados; no se generan automáticamente desde 0–180 grados.

Cada programa guarda `profileVersion`, `profileHash`, `kinematicsVersion`, `homeRevision` y orientación fija además de puntos, garra, velocidad y pausas. Los ángulos son solo auditoría. Cambiar geometría, home, límites o calibración marca programas como `needsRevalidation`; nunca actualiza esas referencias silenciosamente. Revalidar crea una revisión y exige confirmación del operador sobre los puntos resultantes antes de ejecutar.

La configuración se carga como borrador, valida y activa atómicamente únicamente sin ejecución ni salida de calibración activa. No habilita actuadores ni limpia fallos. Una transferencia incompleta conserva el perfil anterior. La activación invalida sesiones previas y cualquier validación de programa incompatible.

## Criterios de aceptación

| ID | Resultado comprobable |
| --- | --- |
| AC-01 | Bloqueo por software durante cualquier modo cancela ejecución e impide nuevas consignas. Reconexión y reinicio no rearman. Solo resetLatch explícito válido permite volver a BOOT_LOCKED, sin movimiento; órdenes de rearme repetidas, vencidas o de otro enclavamiento se rechazan. |
| AC-02 | Pérdida de control durante un paso inicia parada dentro del plazo validado; no ejecuta pasos posteriores ni reanuda al reconectar. |
| AC-03 | J2 rechaza atómicamente un objetivo que incumple cualquiera de los dos límites; un perfil no calibrado bloquea operación normal. |
| AC-04 | App y firmware producen la misma selección dentro de tolerancias del algoritmo; rechazan alcance, orientación, trayectoria o parada inválidos. |
| AC-05 | Órdenes duplicadas, retenidas, vencidas, fuera de orden, de otra sesión/robot o con perfil distinto no generan movimiento. |
| AC-06 | Un programa recuperado de nube conserva puntos, garra, velocidad y pausas; cambiar perfil/home impide ejecutarlo hasta revalidar una nueva revisión. |
| AC-07 | Ninguna pantalla informa conexión, aceptación, parada o llegada física a partir de una pulsación local; distingue estado confirmado, estimado y desconocido. |
| AC-08 | QR consumido/expirado y cuenta ajena no obtienen control; revocar autorización impide renovar sesión y detiene ejecución al vencer la vigente. |
| AC-09 | Arranque, retorno de energía y reinicio durante emergencia no inician movimiento; referencia desconocida bloquea TCP y programas. |

## Registro de decisiones físicas del propietario

| ID | Estado e información | Efecto |
| --- | --- | --- |
| D-01 | Resuelta: el propietario declara que la caída al perder energía es aceptable para este modelo pequeño. | No se exige retención mecánica ante pérdida de energía; no se deduce que exista corte controlado. |
| D-02 | Resuelta: el propietario excluye pulsador físico y circuito de corte por el momento. | Parada y rearme por software; no bloquea esta etapa ni promete corte eléctrico. |
| D-03 | CAD/esquema de ejes y postura de referencia, seguido de calibración física. | Cinemática y trayectoria cartesiana; los valores físicos no se deducen de las longitudes. |

Los pines, límites articulares, pulsos, velocidad, aceleración, tolerancias mecánicas y tiempos admisibles de detección/parada se obtienen del montaje y pruebas. Pueden implementarse simulación, contratos y lógica mientras permanecen pendientes; no se rellenan con supuestos para activar hardware.


## Ajuste de alcance — 13 de septiembre de 2026

Por decisión del usuario, se pospone la autorización por propietario y las ACL específicas por robot. Todos los usuarios autenticados pueden consultar los robots registrados y solicitar su sesión de control. La asociación mediante QR es opcional para el acceso. Esta decisión prevalece sobre los apartados anteriores que exigen aislamiento por propietario.

La conexión inicial confirma una respuesta del ESP32 y presenta un indicador de conexión en curso, éxito o error. No exige calibración ni programas guardados. Se mantienen TLS, autenticación general, vigencia de mensajes, validación de destino/arranque, sesión exclusiva y límites locales de movimiento. Conectar no habilita ni mueve servos. El simulador se identifica por separado.
