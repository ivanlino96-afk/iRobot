# Diseño de AiRobot

Referencia solicitada: https://chatgpt.com/codex/, inspeccionada el 13 de septiembre de 2026 mediante captura y estilos calculados del navegador.

- La referencia utiliza OpenAI Sans, texto #0d0d0d y secundario #5d5d5d.
- Botones principales negros, blancos en texto, con forma de píldora.
- Jerarquía de títulos de peso regular, espacio amplio y fondos azul/lavanda suaves.
- AiRobot conserva identidad propia, reserva el rojo para bloqueo y muestra estado confirmado fuera del área decorativa.
- En móvil se utiliza navegación inferior; desde 800 px se usa navegación lateral. Las acciones de parada permanecen disponibles arriba de todas las pantallas.

El tema está en `app/lib/presentation/theme.dart`. Se usa tipografía del sistema, con SF Pro en iOS; no se incluye OpenAI Sans porque no se ha confirmado una licencia para redistribuir su archivo. `AIROBOT_FONT_FAMILY` permite elegir una familia incorporada explícitamente en pubspec si se dispone del archivo y autorización correspondiente. El reemplazo tipográfico está documentado y no se presenta como una coincidencia exacta.

Las vistas previas se generan con `flutter test --dart-define=CAPTURE_PREVIEWS=true test/visual_test.dart` y la biblioteca nativa de pruebas configurada según la guía. En macOS, la captura carga SF Pro desde el sistema para evitar la fuente Ahem de pruebas; no copia ni distribuye el archivo de fuente.
