import 'dart:async';
import 'dart:isolate';
import 'package:airobot_kinematics/airobot_kinematics.dart';
import '../domain/models.dart';

class SimulatorRepository implements RobotRepository {
  SimulatorRepository(this.profile, this.math) {
    robot = NativeRobot(math, profile.nativeValues);
    timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }
  RobotProfile profile;
  final NativeKinematics math;
  late NativeRobot robot;
  final watch = Stopwatch()..start();
  Timer? timer;
  final _states = StreamController<RobotSnapshot>.broadcast();
  final saved = <Map<String, dynamic>>[];
  RobotSnapshot snapshot = const RobotSnapshot(simulation: true);
  bool link = true;
  int generation = 0;
  bool disposed = false;
  @override
  Stream<RobotSnapshot> get states => _states.stream;
  void _tick() {
    final s = robot.tick(watch.elapsedMilliseconds, link);
    final names = [
      'BOOT_LOCKED',
      'UNCALIBRATED',
      'CALIBRATING',
      'READY',
      'EXECUTING',
      'STOPPING',
      'HOLD',
      'FAULT',
      'ESTOP_LATCHED',
    ];
    snapshot = RobotSnapshot(
      connected: true,
      state: names[s.$1],
      joints: s.$2,
      tcp: s.$3 && profile.geometry
          ? math.forward(profile.nativeValues, s.$2)
          : null,
      reference: s.$3,
      simulation: true,
      bootId: 'simulation',
      profileHash: profile.hash,
      latchId: 'simulation-latch',
      resetNonce: 'simulation-reset',
    );
    _states.add(snapshot);
  }

  @override
  Future<void> command(String type, Map<String, dynamic> payload) async {
    if (disposed) throw StateError('Simulador desconectado');
    if (['stop', 'emergencyStop', 'resetLatch'].contains(type)) generation++;
    final commandGeneration = generation;
    int code;
    List<double>? q;
    int speed = payload['speedPercent'] ?? 10;
    switch (type) {
      case 'confirmReference':
        code = 1;
        q = RobotProfile.numbers(payload['jointDegrees'], 7);
        break;
      case 'enable':
        code = 2;
        link = true;
        break;
      case 'emergencyStop':
        code = 3;
        break;
      case 'resetLatch':
        code = 4;
        break;
      case 'stop':
        code = 5;
        break;
      case 'acknowledgeHold':
        code = 6;
        link = true;
        break;
      case 'disconnectTest':
        link = false;
        return;
      case 'goHome':
        code = 7;
        q = profile.home;
        break;
      case 'moveJoint':
        code = 7;
        q = List.of(snapshot.joints);
        q[payload['joint'] as int] = (payload['degrees'] as num).toDouble();
        break;
      case 'moveTcp':
        code = 7;
        final values = List<double>.of(profile.nativeValues);
        final from = List<double>.of(snapshot.joints);
        final tcp = RobotProfile.numbers(payload['tcp'], 3);
        final keep = payload['orientation'] == 'current';
        q = await Isolate.run(
          () => NativeKinematics().plan(
            values,
            from,
            tcp,
            speed,
            keepOrientation: keep,
          ),
        );
        if (disposed ||
            generation != commandGeneration ||
            snapshot.state != 'READY') {
          throw StateError('Movimiento simulado cancelado');
        }
        if (q == null) {
          throw StateError('Punto fuera de alcance');
        }
        q[6] = (payload['gripperDegrees'] as num).toDouble();
        break;
      case 'runProgram':
        if (payload['profileHash'] != profile.hash) {
          throw StateError('Perfil incompatible');
        }
        var from = snapshot.joints;
        final plan = <List<double>>[];
        for (final raw in payload['steps']) {
          final s = ProgramStep.fromJson(Map<String, dynamic>.from(raw));
          final target = math.plan(profile.nativeValues, from, s.tcp, s.speed);
          target[6] = s.gripper;
          plan.add([...target, s.speed.toDouble(), s.pauseMs.toDouble()]);
          from = target;
        }
        if (!robot.program(plan, watch.elapsedMilliseconds)) {
          throw StateError('Programa rechazado');
        }
        _tick();
        return;
      default:
        throw StateError('Orden no soportada');
    }
    if (!robot.command(code, q, speed, watch.elapsedMilliseconds)) {
      throw StateError('Orden rechazada por estado, límites o trayectoria');
    }
    _tick();
  }

  @override
  Future<void> activateProfile(RobotProfile p) async {
    generation++;
    if ([
      'EXECUTING',
      'STOPPING',
      'ESTOP_LATCHED',
      'FAULT',
    ].contains(snapshot.state)) {
      throw StateError('Estado incompatible');
    }
    if (!math.validate(p.nativeValues)) throw StateError('Perfil inválido');
    robot.dispose();
    profile = p;
    robot = NativeRobot(math, p.nativeValues);
    _tick();
  }

  @override
  Future<List<Map<String, dynamic>>> programs() async => saved
      .map(
        (p) => {
          ...p,
          'needsRevalidation': p['body']['profileHash'] != profile.hash,
        },
      )
      .toList();
  @override
  Future<void> saveProgram(
    String name,
    Map<String, dynamic> body, {
    String? sourceId,
  }) async {
    saved.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name,
      'body': body,
      'sourceId': ?sourceId,
      'revision': 1,
    });
  }

  @override
  Future<void> deleteProgram(String id) async {
    saved.removeWhere((p) => p['id'] == id);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    generation++;
    timer?.cancel();
    robot.dispose();
    watch.stop();
    await _states.close();
  }
}
