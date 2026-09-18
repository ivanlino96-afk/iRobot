import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:airobot_kinematics/airobot_kinematics.dart';
import '../domain/models.dart';
import '../data/simulator_repository.dart';
import '../data/mqtt_connectivity_probe.dart';
import '../data/mqtt_robot_repository.dart';
import '../infrastructure/api_client.dart';
import '../infrastructure/event_log.dart';

Future<List<double>> solveTcp(
  List<double> profile,
  List<double> from,
  List<double> target,
  int speed, {
  bool keepOrientation = false,
}) => Isolate.run(
  () => NativeKinematics().plan(
    profile,
    from,
    target,
    speed,
    keepOrientation: keepOrientation,
  ),
);

class RobotViewModel extends ChangeNotifier {
  int commandGeneration = 0;
  String? editingProgramId;
  void ensureMotion(int generation) {
    if (generation != commandGeneration ||
        !snapshot.canMove ||
        profile?.hash != snapshot.profileHash) {
      throw StateError('El movimiento se canceló o cambió el estado del robot');
    }
  }

  RobotRepository? repository;
  final eventLog = RobotEventLog();
  bool get reconnecting =>
      repository is MqttRobotRepository &&
      (repository as MqttRobotRepository).reconnecting;
  int get reconnectAttempt => repository is MqttRobotRepository
      ? (repository as MqttRobotRepository).reconnectAttempt
      : 0;
  String? get lastDisconnectReason => repository is MqttRobotRepository
      ? (repository as MqttRobotRepository).lastDisconnectReason
      : null;
  RobotProfile? profile;
  RobotSnapshot snapshot = const RobotSnapshot();
  ApiClient? api;
  NativeKinematics? math;
  StreamSubscription? subscription;
  String message = 'Conecta tu robot o explora el simulador', robotId = '';
  String robotName = 'MKT100';
  void setRobotName(String name) {
    if (name.trim().isNotEmpty) {
      robotName = name.trim();
      notifyListeners();
    }
  }

  ThemeMode themeMode = ThemeMode.system;
  void setThemeMode(ThemeMode mode) {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
  }

  bool connecting = false;
  bool get simulationMode => repository is SimulatorRepository;
  String get stateLabel => switch (snapshot.state) {
    'READY' => 'Listo',
    'EXECUTING' => 'En movimiento',
    'STOPPING' => 'Deteniendo',
    'HOLD' => 'En pausa',
    'BOOT_LOCKED' => 'Desarmado',
    'UNCALIBRATED' => 'Sin calibrar',
    'CALIBRATING' => 'Calibrando',
    'FAULT' => 'Revisar robot',
    'ESTOP_LATCHED' => 'Bloqueado',
    _ => 'Sin conexión',
  };

  Future<void> setSimulationMode(bool enabled) async {
    if (enabled == simulationMode) return;
    commandGeneration++;
    if (enabled) {
      if (repository != null && snapshot.connected) await send('stop');
      await demo();
      await reference(profile!.home);
      await send('enable');
    } else {
      await subscription?.cancel();
      subscription = null;
      await repository?.dispose();
      repository = null;
      profile = null;
      snapshot = const RobotSnapshot();
      robotId = '';
      saved = [];
      steps.clear();
      editingProgramId = null;
    }
    connectionError = null;
    notifyListeners();
  }

  String? connectionError;
  bool connectivityProbeRunning = false;
  ConnectivityProbeResult connectivityProbe = ConnectivityProbeResult.idle();
  String? connectivityProbeRobotId;

  String? get selectedProbeRobotId {
    if (connectivityProbeRobotId != null &&
        robots.contains(connectivityProbeRobotId)) {
      return connectivityProbeRobotId;
    }
    if (robotId.isNotEmpty && robotId != 'SIMULADOR' && robots.contains(robotId)) {
      return robotId;
    }
    return robots.isEmpty ? null : robots.first;
  }

  void selectProbeRobot(String? id) {
    connectivityProbeRobotId = id;
    connectivityProbe = ConnectivityProbeResult.idle();
    notifyListeners();
  }

  Future<void> testRemoteConnectivity() async {
    final id = selectedProbeRobotId;
    if (api == null || id == null) {
      throw StateError('Inicia sesión y selecciona un robot emparejado');
    }
    if (connectivityProbeRunning) return;
    connectivityProbeRunning = true;
    connectivityProbe = ConnectivityProbeResult(
      api: ConnectivityProbeStage.checking,
      broker: ConnectivityProbeStage.pending,
      robot: ConnectivityProbeStage.pending,
      message: 'Preparando la prueba segura…',
    );
    notifyListeners();
    try {
      final result = await MqttConnectivityProbe(api!, id).run(
        onUpdate: (next) {
          connectivityProbe = next;
          notifyListeners();
        },
      );
      connectivityProbe = result;
      eventLog.add('connectivity-probe', result.message);
    } finally {
      connectivityProbeRunning = false;
      notifyListeners();
    }
  }

  String get connectionLabel => connecting
      ? 'Conectando…'
      : robotId == 'SIMULADOR' && snapshot.connected
      ? 'Simulador'
      : snapshot.connected
      ? 'ESP32 conectado'
      : connectionError != null
      ? 'Error de conexión'
      : 'Conectar';
  String motionStatus = '';
  bool motionPopupVisible = false;
  bool motionUnconfirmed = false;
  bool emergencyPending = false;

  void dismissMotionNotice() {
    if (!motionUnconfirmed) return;
    motionPopupVisible = false;
    notifyListeners();
  }

  Future<void> emergencyStopMotion() async {
    if (emergencyPending) return;
    holding = false;
    _holdEpoch++;
    emergencyPending = true;
    motionStatus = 'Solicitando parada de emergencia…';
    notifyListeners();
    try {
      await send('emergencyStop');
      // Only telemetry confirms that the robot has stopped.
    } catch (_) {
      motionUnconfirmed = true;
      motionStatus =
          'No se pudo confirmar la parada. Revisa la conexión y utiliza la parada física.';
      rethrow;
    } finally {
      emergencyPending = false;
      notifyListeners();
    }
  }

  int _motionCompletions = 0;
  bool holding = false;
  int _holdEpoch = 0;
  bool get canReference =>
      !busy &&
      snapshot.connected &&
      snapshot.state == 'BOOT_LOCKED' &&
      profile?.calibrated == true;

  Future<void> stopMotion() async {
    holding = false;
    _holdEpoch++;
    motionStatus = 'Deteniendo movimiento…';
    notifyListeners();
    try {
      await send('stop');
      if (snapshot.state == 'HOLD') motionStatus = 'Movimiento detenido';
    } catch (_) {
      motionStatus = 'Parada sin confirmar';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Repeats bounded, firmware-validated targets. Never queues ahead of READY.
  /// Releasing, leaving the screen or the 10 s deadline cancels pending IK.
  Future<void> holdJog(Future<void> Function() step) async {
    if (!canMove || holding) return;
    holding = true;
    final epoch = ++_holdEpoch;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    final cutoff = Timer(const Duration(seconds: 10), () {
      if (epoch == _holdEpoch) {
        stopMotion().catchError((Object e) {
          message = '$e';
        });
      }
    });
    notifyListeners();
    try {
      while (holding &&
          epoch == _holdEpoch &&
          DateTime.now().isBefore(deadline)) {
        if (!snapshot.connected ||
            ['FAULT', 'ESTOP_LATCHED', 'HOLD'].contains(snapshot.state)) {
          break;
        }
        if (snapshot.canMove) {
          final completed = _motionCompletions;
          await step();
          // An acknowledgement alone must never enqueue another movement.
          while (holding &&
              epoch == _holdEpoch &&
              _motionCompletions == completed &&
              snapshot.connected &&
              !['FAULT', 'ESTOP_LATCHED', 'HOLD'].contains(snapshot.state) &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    } finally {
      cutoff.cancel();
      if (epoch == _holdEpoch) await stopMotion();
    }
  }

  String? coordinateError(String text, {bool gripper = false}) {
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || !value.isFinite) return 'Introduce un número válido';
    if (gripper &&
        profile != null &&
        (value < profile!.minimum[6] || value > profile!.maximum[6])) {
      return '${profile!.minimum[6]}–${profile!.maximum[6]}°';
    }
    return null;
  }

  bool busy = false;
  bool actionFailed = false;
  String? actionFeedback;
  final steps = <ProgramStep>[];
  List<Map<String, dynamic>> saved = [];
  List<String> robots = [];
  bool get canMove =>
      !busy &&
      !holding &&
      snapshot.canMove &&
      profile?.hash == snapshot.profileHash;
  bool get canArm =>
      !busy &&
      snapshot.connected &&
      snapshot.reference &&
      profile?.hash == snapshot.profileHash &&
      ['BOOT_LOCKED', 'HOLD'].contains(snapshot.state);
  bool get canDisarm =>
      !busy &&
      snapshot.connected &&
      ['READY', 'EXECUTING'].contains(snapshot.state);
  Future<void> arm() async {
    if (!snapshot.connected ||
        !snapshot.reference ||
        profile?.hash != snapshot.profileHash ||
        !['BOOT_LOCKED', 'HOLD'].contains(snapshot.state)) {
      throw StateError('Robot sin referencia o no disponible');
    }
    await send(snapshot.state == 'HOLD' ? 'acknowledgeHold' : 'enable');
  }

  Future<void> disarm() async {
    if (!snapshot.connected ||
        !['READY', 'EXECUTING'].contains(snapshot.state)) {
      throw StateError('Robot no disponible');
    }
    await send('stop');
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy || holding) return;
    busy = true;
    actionFailed = false;
    actionFeedback = null;
    notifyListeners();
    try {
      await action();
      message = actionFeedback ?? 'Cambios guardados';
    } catch (e) {
      actionFailed = true;
      message = e.toString().replaceFirst(
        RegExp(r'^(Bad state: |StateError: |FormatException: )'),
        '',
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> attach(RobotRepository r) async {
    commandGeneration++;
    _holdEpoch++;
    holding = false;
    motionStatus = '';
    motionPopupVisible = false;
    motionUnconfirmed = false;
    await subscription?.cancel();
    await repository?.dispose();
    repository = r;
    subscription = r.states.listen((s) {
      final previous = snapshot.state;
      snapshot = s;
      if (!s.connected) {
        holding = false;
        _holdEpoch++;
        commandGeneration++;
        motionUnconfirmed = true;
        motionStatus = 'Movimiento sin confirmar: conexión perdida';
      } else if (s.state == 'EXECUTING') {
        motionPopupVisible = true;
        motionUnconfirmed = false;
        motionStatus = 'En movimiento';
      } else if (s.state == 'READY' && previous == 'EXECUTING') {
        _motionCompletions++;
        motionPopupVisible = holding;
        motionUnconfirmed = false;
        motionStatus = 'Movimiento completado';
      } else if (s.state == 'HOLD') {
        motionPopupVisible = false;
        motionUnconfirmed = false;
        motionStatus = 'Movimiento detenido';
      } else if (['FAULT', 'ESTOP_LATCHED'].contains(s.state)) {
        motionPopupVisible = false;
        motionUnconfirmed = false;
        motionStatus = 'Movimiento interrumpido';
      }
      if (!s.connected && !connecting && robotId != 'SIMULADOR') {
        connectionError = 'Se perdió la comunicación con el ESP32';
      }
      notifyListeners();
    });
  }

  Future<void> demo() async {
    math ??= NativeKinematics();
    final raw = await rootBundle.loadString('assets/profile.simulation.json');
    profile = RobotProfile(raw, sha256.convert(utf8.encode(raw)).toString());
    robotId = 'SIMULADOR';
    await attach(SimulatorRepository(profile!, math!));
    connectionError = null;
    editingProgramId = null;
    saved = [];
    steps.clear();
  }

  Future<void> login(
    String url,
    String email,
    String password,
    bool register,
  ) async {
    api = ApiClient(url);
    await api!.login(email, password, register: register);
    robots = (await api!.get('/robots') as List)
        .map((e) => e['id'] as String)
        .toList();
    notifyListeners();
  }

  Future<void> pair(String qr) async {
    final data = jsonDecode(qr);
    if (data is! Map ||
        data['robotId'] is! String ||
        data['token'] is! String) {
      throw const FormatException('QR inválido');
    }
    await api!.post('/pair', {
      'robotId': data['robotId'],
      'token': data['token'],
    });
    robots = (await api!.get('/robots') as List)
        .map((e) => e['id'] as String)
        .toList();
    notifyListeners();
  }

  Future<void> connect(String id) async {
    if (api == null) throw StateError('Inicia sesión');
    connecting = true;
    connectionError = null;
    snapshot = snapshot.disconnected();
    notifyListeners();
    try {
      robotId = id;
      // Connection confirmation must not depend on calibration or saved programs.
      profile = null;
      await api!.delete('/robots/$id/session');
      final r = MqttRobotRepository(api!, id, null, log: eventLog);
      await attach(r);
      await r.connect().timeout(const Duration(seconds: 15));
      try {
        final p = await api!.get('/robots/$id/profile');
        profile = RobotProfile(p['profileJson'], p['profileHash']);
        r.profile = profile;
        math ??= NativeKinematics();
        await loadPrograms();
      } catch (e) {
        message = 'ESP32 conectado. Configuración pendiente: $e';
      }
    } catch (e) {
      await repository?.dispose();
      repository = null;
      snapshot = snapshot.disconnected();
      connectionError = 'No se pudo confirmar la conexión con el ESP32: $e';
      throw StateError(connectionError!);
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> send(
    String type, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (repository == null) throw StateError('Conecta primero');
    if (['stop', 'emergencyStop', 'resetLatch'].contains(type)) {
      commandGeneration++;
    }
    final isMovement = [
      'moveJoint',
      'moveTcp',
      'goHome',
      'runProgram',
    ].contains(type);
    final generation = commandGeneration;
    if (isMovement) {
      motionPopupVisible = true;
      motionUnconfirmed = false;
      motionStatus = 'Enviando movimiento…';
      notifyListeners();
    }
    try {
      await repository!.command(type, payload);
      if (isMovement &&
          generation == commandGeneration &&
          motionStatus == 'Enviando movimiento…') {
        motionStatus = 'Orden aceptada · esperando ejecución';
      }
    } catch (_) {
      if (isMovement && generation == commandGeneration) {
        motionUnconfirmed = true;
        motionStatus = 'Movimiento sin confirmar';
      }
      rethrow;
    } finally {
      notifyListeners();
    }
    if (isMovement && generation != commandGeneration) {
      throw StateError('Movimiento cancelado por una parada');
    }
    actionFeedback = switch (type) {
      'moveJoint' || 'moveTcp' => 'Movimiento enviado',
      'goHome' => 'Regreso a home iniciado',
      'stop' => 'Parada solicitada',
      'emergencyStop' => 'Movimiento bloqueado',
      'enable' || 'acknowledgeHold' => 'Control habilitado',
      'resetLatch' => 'Bloqueo restablecido. Confirma la referencia',
      'confirmReference' => 'Referencia confirmada',
      'runProgram' => 'Programa iniciado',
      'disconnectTest' => 'Pérdida de control simulada',
      _ => 'Orden confirmada',
    };
  }

  Future<void> reference(List<double> q) async =>
      send('confirmReference', {'jointDegrees': q, 'operatorConfirmed': true});
  Future<void> moveJoint(int joint, double degrees, int speed) async {
    if (!snapshot.canMove || profile?.hash != snapshot.profileHash) {
      throw StateError('Robot no disponible');
    }
    final to = List<double>.of(snapshot.joints)..[joint] = degrees;
    if (!math!.path(profile!.nativeValues, snapshot.joints, to, speed)) {
      throw StateError('Límites o trayectoria inválidos');
    }
    await send('moveJoint', {
      'joint': joint,
      'degrees': degrees,
      'speedPercent': speed,
    });
  }

  Future<void> tcp(
    List<double> target,
    int speed,
    double gripper, {
    bool keepOrientation = false,
  }) async {
    if (!snapshot.canMove ||
        profile == null ||
        profile?.hash != snapshot.profileHash) {
      throw StateError('Robot no disponible');
    }
    final generation = commandGeneration;
    motionPopupVisible = true;
    motionUnconfirmed = false;
    motionStatus = 'Validando trayectoria…';
    notifyListeners();
    try {
      final q = await solveTcp(
        profile!.nativeValues,
        List.of(snapshot.joints),
        target,
        speed,
        keepOrientation: keepOrientation,
      );
      q[6] = gripper;
      ensureMotion(generation);
      if (!math!.path(profile!.nativeValues, snapshot.joints, q, speed)) {
        throw StateError('Trayectoria inválida');
      }
      await send('moveTcp', {
        'tcp': target,
        'speedPercent': speed,
        'gripperDegrees': gripper,
        'pauseMs': 0,
        'orientation': keepOrientation ? 'current' : 'home',
      });
    } catch (_) {
      if (generation == commandGeneration &&
          motionStatus == 'Validando trayectoria…') {
        motionPopupVisible = false;
      }
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> jogAxis(int axis, double millimeters, int speed) async {
    if (!snapshot.canMove ||
        snapshot.tcp == null ||
        profile?.geometry != true) {
      throw StateError('Posición TCP no disponible');
    }
    final target = List<double>.of(snapshot.tcp!);
    target[axis] += millimeters;
    await tcp(target, speed, snapshot.joints[6], keepOrientation: true);
  }

  Future<void> jogGripper(int joint, double degrees, int speed) async {
    if (joint != 5 && joint != 6) throw ArgumentError('Articulación inválida');
    await moveJoint(joint, snapshot.joints[joint] + degrees, speed);
  }

  void teach(int speed, int pause, {String name = ''}) {
    if (!snapshot.reference || snapshot.tcp == null) {
      throw StateError('No hay TCP estimado válido');
    }
    if (steps.length >= 32) throw StateError('Máximo 32 pasos');
    steps.add(
      ProgramStep(
        tcp: List.of(snapshot.tcp!),
        gripper: snapshot.joints[6],
        speed: speed,
        pauseMs: pause,
        name: name,
      ),
    );
    notifyListeners();
  }

  bool get isIdle => !busy && !holding && snapshot.state == 'READY';

  void discardSteps() {
    steps.clear();
    editingProgramId = null;
    notifyListeners();
  }

  Map<String, dynamic> body() => {
    'profileVersion': profile!.version,
    'profileHash': profile!.hash,
    'homeRevision': profile!.json['homeRevision'],
    'kinematicsVersion': 'ik-dls-1',
    'orientation': 'home',
    'confirmed': true,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
  Future<void> save(String name) async {
    if (profile == null || steps.isEmpty || name.trim().isEmpty) {
      throw StateError('Agrega puntos y un nombre');
    }
    await repository!.saveProgram(name, body(), sourceId: editingProgramId);
    await loadPrograms();
  }

  Future<void> loadPrograms() async {
    saved = await repository!.programs();
    notifyListeners();
  }

  Future<void> run(Map<String, dynamic> program) async {
    final b = Map<String, dynamic>.from(program['body']);
    if (b['profileHash'] != profile?.hash) {
      throw StateError('Revalida el programa con el perfil actual');
    }
    var from = snapshot.joints;
    for (final raw in b['steps']) {
      final s = ProgramStep.fromJson(Map<String, dynamic>.from(raw));
      final q = math!.plan(profile!.nativeValues, from, s.tcp, s.speed)
        ..[6] = s.gripper;
      if (!math!.path(profile!.nativeValues, from, q, s.speed)) {
        throw StateError('Trayectoria inválida');
      }
      from = q;
    }
    await send('runProgram', b);
  }

  void editProgram(Map<String, dynamic> p) {
    editingProgramId = p['id'];
    steps.clear();
    for (final raw in p['body']['steps']) {
      steps.add(ProgramStep.fromJson(Map<String, dynamic>.from(raw)));
    }
    notifyListeners();
  }

  Future<void> revalidate(Map<String, dynamic> p) async {
    editProgram(p);
    final candidate = {'body': body()};
    var from = snapshot.joints;
    for (final s in steps) {
      final q = math!.plan(profile!.nativeValues, from, s.tcp, s.speed)
        ..[6] = s.gripper;
      if (!math!.path(profile!.nativeValues, from, q, s.speed)) {
        throw StateError('Revalidación fallida');
      }
      from = q;
    }
    await repository!.saveProgram(
      '${p['name']} · revisión',
      candidate['body'] as Map<String, dynamic>,
      sourceId: p['id'],
    );
    await loadPrograms();
  }

  Future<void> applyProfile(String text) async {
    math ??= NativeKinematics();
    final json = jsonDecode(text);
    final canonical = jsonEncode(json);
    var p = RobotProfile(
      canonical,
      sha256.convert(utf8.encode(canonical)).toString(),
    );
    if (!math!.validate(p.nativeValues)) {
      throw StateError('Perfil mecánico inválido');
    }
    if (repository is MqttRobotRepository) {
      final response = await api!.post('/robots/$robotId/profile', json);
      p = RobotProfile(response['profileJson'], response['profileHash']);
    }
    await repository!.activateProfile(p);
    profile = p;
    await loadPrograms();
  }

  Future<void> reset() async {
    if (repository is MqttRobotRepository) {
      await connect(robotId);
    }
    await send('resetLatch', {
      'latchId': snapshot.latchId,
      'resetNonce': snapshot.resetNonce,
    });
  }

  Future<void> suspend() async {
    try {
      if (holding) await stopMotion();
      if (snapshot.canMove || snapshot.state == 'EXECUTING') await send('stop');
    } finally {
      if (repository is MqttRobotRepository) {
        await repository!.dispose();
        repository = null;
        snapshot = snapshot.disconnected();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    holding = false;
    _holdEpoch++;
    commandGeneration++;
    subscription?.cancel();
    repository?.dispose();
    eventLog.dispose();
    super.dispose();
  }
}
