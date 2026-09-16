# Control manual

Manual utiliza la consigna conocida del controlador; los MG995 no miden posición.
El TCP se expresa en milímetros respecto al home configurado. J6 controla la
rotación de la garra y J7 su apertura. La trayectoria entre destinos es articular,
no una garantía de línea recta en el espacio.

- Servo: seleccionar J1–J7, ajustar el objetivo y pulsar Mover. J2 conserva la
  coordinación y calibración independiente de sus dos servos físicos.
- Flechas: un toque envía un paso; mantener pulsado repite destinos acotados,
  esperando telemetría de ejecución y finalización antes del siguiente. Los pasos
  lineales y angulares son configurables en 1, 5 o 10 mm/grados. Soltar, arrastrar
  fuera, abrir el menú, cambiar de modo/pantalla o pasar a segundo plano cancela
  el gesto y solicita parada. Cada gesto dura como máximo 10 segundos.
- Coordenadas: cargar la posición objetivo vigente, introducir X/Y/Z y apertura,
  elegir orientación actual o de home y validar. Los errores numéricos y de
  apertura aparecen en el campo; alcance y trayectoria se validan con cinemática.
- La parada evita el bloqueo `busy` de las acciones de UI y cancela cálculos IK
  anteriores mediante su generación. Una orden aceptada no equivale a llegada:
  la finalización se muestra cuando la telemetría cambia de EXECUTING a READY.

## Compatibilidad de orientación

`moveTcp.payload.orientation` acepta `home` y, con este firmware, `current`.
`current` toma la orientación cartesiana calculada desde la consigna articular
actual del controlador, conservando el origen de coordenadas en home. Los
programas guardados siguen usando `home`. La biblioteca nativa incorpora
`airobot_plan_current`; se requiere reconstruir la app. Para usar `current` en un
robot físico hay que instalar el firmware que incluye esta validación; versiones
anteriores rechazan el modo y no deben tratarlo silenciosamente como `home`.

La pulsación sostenida es repetición de pasos, no streaming de velocidad. La
pérdida de enlace se maneja localmente por el watchdog y la parada del firmware;
la orden de parada de la app requiere comunicación. La parada física de
emergencia continúa siendo independiente de la interfaz y de Internet.

## Verificación

Pruebas nativas: orientación conservada, rechazo fuera de alcance y validación
`home/current` en el protocolo, además de límites, J2, parada y pérdida de enlace.
Pruebas Flutter: parada durante IK, telemetría de finalización, ausencia de cola
sin telemetría, fin de pulsación sostenida, desconexión y entradas inválidas.
Estas pruebas no sustituyen la calibración ni las pruebas físicas a baja velocidad.
