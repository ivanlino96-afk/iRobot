# MG995: control directo por puerto serie

Esta versión sustituye la prueba con interpolación. No usa Motion.h, Preferences, calibración persistida, tiempos de trayectoria ni un estado ocupado. Cada ángulo se escribe directamente al PCA9685 y sustituye la consigna anterior. No necesita conocer la posición física del servo ni espera una confirmación del MG995.

## Carga y conexión

Abrir ServoBench.ino en Arduino IDE. Instalar Adafruit PWM Servo Driver Library con Adafruit BusIO. Elegir la placa real ESP32-C3, activar USB CDC On Boot y cargar. Monitor a 115200 baudios con Nueva línea. En PlatformIO utilizar `pio run -e servo_bench -t upload` desde firmware.

- GPIO8 -> SDA; GPIO9 -> SCL, como confirmó el usuario.
- ESP32 3.3V -> VCC lógico del PCA9685.
- Masa común entre ESP32, PCA9685 y fuente externa de servos.
- Fuente de servos -> V+; no alimentar los servos desde el ESP32.
- PCA9685 dirección 0x40 y frecuencia 50 Hz.

GPIO8/9 afectan al arranque del ESP32-C3. Si no arranca, probar con el ESP32 aislado del módulo y revisar que GPIO9 no permanezca bajo al encender. Tras abrir el monitor aparece la ayuda; también se puede enviar `ayuda`.

## Comandos

```text
canal 0
90
0
90
canal 1
95
canal 7
90
estado
apagar
```

Enviar una línea cada vez. No hay espera impuesta por el programa; el movimiento físico del servo sí tarda en realizarse.

| Comando | Resultado |
| --- | --- |
| canal N | Selecciona 0..7; seleccionar 1 o 2 activa la selección del mismo par |
| 90 o mover 90 | Envía directamente el ángulo indicado |
| estado | Muestra canal seleccionado y última consigna enviada por canal |
| apagar | Apaga pulsos de todos los canales; deja de sostener activamente la carga |
| i2c | Busca direcciones I2C, para diagnosticar el PCA9685 |
| ayuda | Muestra los comandos actuales |

Seleccionar un canal NO mueve ni apaga otros servos: conservan su última consigna. Al encender el ESP32 se apagan las salidas hasta recibir un ángulo. El par 1–2 siempre recibe `angulo` y `180-angulo`, incluso si se seleccionó `canal 2`. No se aplican offsets de la versión anterior. Los comandos antiguos iniciar, confirmar, config, velocidad, parar, bloquear y rearmar ya no forman parte de este sketch simple.

## Qué significan los mensajes

`Canal 0: consigna 0.0 -> 90.0 grados` significa que se sustituyó la orden de 0° por una de 90°. NO significa que el servo alcanzó ninguno de esos ángulos. MG995 no devuelve al ESP32 su posición, avance o finalización. El programa no simula ni imprime avance físico ficticio.

Se conserva la escala del ejemplo original: SERVOMIN=150 y SERVOMAX=600 cuentas a 50 Hz, aproximadamente 732–2930 microsegundos. Son referencias ajustables en el sketch, no extremos certificados para cada MG995. Se aceptan 0°–180°; si el servo zumba o empuja un tope, interrumpir la prueba y revisar recorrido/pulsos, alimentación y carga. Un MG995 modificado a rotación continua no interpreta estas señales como posiciones angulares.

El fallo de I2C informa que la escritura no pudo confirmarse; no demuestra una parada física. Los dos canales espejo se escriben consecutivamente y un fallo entre ambas escrituras puede dejarlos descoordinados.
