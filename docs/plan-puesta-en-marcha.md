# Plan de puesta en marcha — AR-001 (de código listo a brazo funcionando)

## Estado actual (2026-09-18)
- **Paso 1 (verificación automática de software): cerrado**, con el alcance decidido:
  - `tools/test-core.sh` → verde (`test_core.cpp`, `test_protocol.cpp`, `test_servo_bench.cpp`, chequeo de paridad de headers firmware/app).
  - `backend`: `npm test` → 4/4 verde.
  - `app/`: `flutter analyze` → limpio; `flutter test` → 51/51 verde (requiere compilar `airobot_kinematics.cpp` a librería nativa local y apuntar `AIROBOT_NATIVE_LIB` a ella — no aplica en Linux/macOS, donde el `.so`/`.dylib` ya se resuelve por el build normal).
  - `tools/build-simulator.sh` y `tools/test-integration.mjs` → **omitidos por decisión del usuario** en esta máquina (falta OpenSSL dev para mingw en Windows sin permisos de admin; no es una regresión de código). Pendiente re-evaluar en una máquina con Docker/OpenSSL disponibles.
- **Paso 2 (emparejamiento pendiente): pendiente**, es tarea del usuario en una red sin inspección TLS corporativa (Zscaler bloquea la prueba en la máquina/emulador original).
- **Pasos 3-6: pendientes**, dependen del Paso 2 y de acceso físico al brazo AR-001.

## Contexto
El "FASE 2" original (wiring de login/pairing en la app) ya está **hecho**: `robot_view_model.dart` ya llama `notifyListeners()` al final de `login()` y `pair()`, y `login_page.dart`/`home_page.dart` ya tienen estado de registro/login, emparejamiento, loading y error conectados. Ese plan queda superado por este.

No existe en el repo un documento literal "FASE 1-6" de despliegue. Lo más cercano y ya verificado línea por línea es:
- `specs/001-airobot-master-control/plan.md` (sección "9. Fases, dependencias y aceptación"): tabla **F0-F7**. **F0-F6 están implementadas en código** (contratos, firmware supervisor, perfil/calibración, backend/QR, app Flutter, cinemática, programas). Solo queda **F7 — "Integración física progresiva y evidencia de aceptación"**, que depende de F1-F6 y de "D-03 y calibración resueltas".
- `docs/instalacion-y-pruebas.md`: checklist numerado 1-7 (backend local → registrar controlador → firmware → app → pruebas automáticas → prueba inicial ESP32 → pruebas físicas). Es el runbook de facto.
- `docs/constitution.md`: invariantes de seguridad que no se pueden relajar durante F7 (parada por software como autoridad final, config versionada y trazable por robot, TLS obligatorio, sin movimiento cartesiano sin geometría/límites validados).
- Ajuste de alcance del 13-sep-2026 (`specs/.../plan.md`): la autorización por propietario y las ACL por robot están **pospuestas por decisión del usuario** — cualquier usuario autenticado puede consultar robots y pedir sesión de control; el QR/pairing es opcional para el acceso. Esto no es una brecha a corregir, es el alcance actual aceptado.

Es decir: **el código (app + backend + firmware) está completo**. Lo que falta para "poner en marcha" el robot real es (a) terminar la prueba de emparejamiento pendiente y (b) la integración física F7, que es trabajo de laboratorio con el brazo real, no más código.

## Pasos, en orden

### 1. Verificación automática de software (antes de tocar hardware real) — ✅ cerrado
Correr lo que ya existe, para tener una base verde antes de F7:
- `tools/test-core.sh` (tests nativos C++: `test_core.cpp`, `test_protocol.cpp`, `test_servo_bench.cpp`)
- `tools/build-simulator.sh` + ejecutar `.build/simulator`
- `tools/test-integration.mjs` (stack local completo: Postgres + Mosquitto TLS + simulador, según `docs/instalacion-y-pruebas.md:68`)
- `backend`: `npm test` (`backend/package.json:1`)
- `app/`: `flutter analyze` y `flutter test`

Criterio de cierre: todo pasa en verde. Si algo falla, es una regresión real a arreglar antes de seguir — no forma parte de F7. (Los dos ítems omitidos en esta máquina quedan documentados arriba en "Estado actual".)

### 2. Completar el emparejamiento pendiente (tarea del usuario, no de la IA)
El bloqueo conocido es de red (Zscaler intercepta TLS en el equipo/emulador original), no del código:
- Completar el registro/login + `POST /pair` en un dispositivo/red sin inspección TLS corporativa.
- Usar la UI ya wireada (`login_page.dart` → `home_page.dart` → "Emparejar robot"), pegando el contenido de `pairing.json` de `AR-001`.
- Si el token ya expiró (TTL 24 h desde que se generó), habrá que re-provisionar ese robot (`backend/src/provision.js`) — eso toca el VPS, así que se hace con confirmación explícita del usuario antes de ejecutar nada ahí.
- Confirmación de éxito: `AR-001` aparece en el dropdown de robots de la app.

### 3. Primera prueba solo-ESP32 (`docs/instalacion-y-pruebas.md` §6)
Con `device.json` ya generado en el paso de provisioning:
- Volcar `mqttUsername`/`mqttPassword` de `device.json` a `firmware/include/secrets.h` (nunca pegar ese contenido en el chat ni commitearlo).
- Flashear el firmware (`firmware/src/main.cpp`) al ESP32.
- Verificar en logs/monitor serie: conexión WiFi, sync NTP, handshake MQTTS contra el CA fijado, publicación en `airobot/v1/robots/AR-001/availability`.
- El robot debe arrancar en `BOOT_LOCKED` (sin habilitar servos) — es el comportamiento esperado, no un fallo.

### 4. Calibración física (`docs/instalacion-y-pruebas.md` §7, cierra F2/F7)
Vía comandos serie ya implementados en el firmware (`commission`, `calibrate`, `reference N deg`, `servo N deg`, `latch`, `end`):
- Medir y fijar límites, offsets, dirección y geometría reales del brazo AR-001 (según el requisito de "config explícita y trazable" de `docs/constitution.md`).
- Confirmar (`commission <hash>`) el perfil resultante, para que quede versionado y verificable por hash.
- Activar el perfil desde el backend (`applyProfile` / `POST /robots/:id/profile` en `robot_view_model.dart:697`) para que app y firmware compartan el mismo `profileHash`.

### 5. Primer movimiento seguro extremo a extremo
Ya con perfil calibrado y activo:
- Desde la app: `connect(id)` → `arm()` → `confirmReference` → un `moveJoint` pequeño y controlado.
- Verificar la transición de telemetría `EXECUTING → READY` (única fuente válida de "movimiento completado", per `docs/manual-control.md`).
- Verificar que `emergencyStopMotion()` detiene físicamente el brazo.
- Esto genera la evidencia de aceptación AC-01..AC-09 que cierra F7 (`specs/001-airobot-master-control/plan.md`).

### 6. (Opcional, no ahora) Revisar ACL por propietario
El ajuste de alcance del 13-sep-2026 pospuso esto por decisión del usuario. No se toca a menos que se pida explícitamente más adelante.

## Archivos relevantes
- `specs/001-airobot-master-control/plan.md` (tabla F0-F7; ajuste de alcance del 13-sep-2026)
- `docs/instalacion-y-pruebas.md` (checklist 1-7)
- `docs/constitution.md` (invariantes de seguridad, no negociables durante F7)
- `firmware/src/main.cpp` (comandos serie de calibración/commissioning)
- `deployment/dokploy/README.md` (referencia del despliegue VPS ya en producción y saludable)
- `app/lib/presentation/{login_page.dart, home_page.dart, robot_view_model.dart}` (flujo de login/pairing/control, ya wireado y funcional)
- `tools/test-core.sh`, `tools/build-simulator.sh`, `tools/test-integration.mjs`, `backend/package.json`

## Restricciones vigentes durante todo el proceso
- No se toca el VPS/infra sin confirmación explícita previa del usuario.
- Nunca imprimir ni commitear el contenido de `device.json`, `pairing.json`, `secrets.h`, `.env`, ni `signing.pem`.
- No exponer 1883/8883 externamente; no eliminar el broker Mosquitto actual.
- No instalar CA de Zscaler en el emulador ni añadir `network-security-config` de depuración — el emparejamiento se completa en una red no interceptada.

## Verificación
Cada paso tiene su propio criterio de cierre descrito arriba (tests en verde → emparejamiento confirmado en la app → ESP32 en `BOOT_LOCKED` con MQTTS ok → perfil comisionado con hash activo → transición `EXECUTING→READY` y e-stop físico confirmados). El cierre final del plan es la evidencia física de AC-01..AC-09 que marca F7 como completo.
