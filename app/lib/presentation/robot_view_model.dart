import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:airobot_kinematics/airobot_kinematics.dart';
import '../domain/models.dart';
import '../data/simulator_repository.dart';
import '../data/mqtt_robot_repository.dart';
import '../infrastructure/api_client.dart';

class RobotViewModel extends ChangeNotifier {
  RobotRepository? repository;
  RobotProfile? profile;
  RobotSnapshot snapshot = const RobotSnapshot();
  ApiClient? api;
  NativeKinematics? math;
  StreamSubscription? subscription;
  String message = 'Conecta tu robot o explora el simulador', robotId = '';
  bool busy = false;
  final steps = <ProgramStep>[];
  List<Map<String, dynamic>> saved = [];
  List<String> robots = [];
  bool get canMove =>
      !busy && snapshot.canMove && profile?.hash == snapshot.profileHash;
  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await action();
      message = 'Operación confirmada';
    } catch (e) {
      message = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> attach(RobotRepository r) async {
    await subscription?.cancel();
    await repository?.dispose();
    repository = r;
    subscription = r.states.listen((s) {
      snapshot = s;
      notifyListeners();
    });
  }

  Future<void> demo() async {
    math ??= NativeKinematics();
    final raw = await rootBundle.loadString('assets/profile.simulation.json');
    profile = RobotProfile(raw, sha256.convert(utf8.encode(raw)).toString());
    robotId = 'SIMULADOR';
    await attach(SimulatorRepository(profile!, math!));
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
  }

  Future<void> connect(String id) async {
    if (api == null) throw StateError('Inicia sesión');
    robotId = id;
    math ??= NativeKinematics();
    try {
      final p = await api!.get('/robots/$id/profile');
      profile = RobotProfile(p['profileJson'], p['profileHash']);
    } catch (_) {
      profile = null;
    }
    await api!.delete('/robots/$id/session');
    final r = MqttRobotRepository(api!, id, profile);
    await attach(r);
    await r.connect();
    await loadPrograms();
  }

  Future<void> send(
    String type, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (repository == null) throw StateError('Conecta primero');
    await repository!.command(type, payload);
  }

  Future<void> reference(List<double> q) async =>
      send('confirmReference', {'jointDegrees': q, 'operatorConfirmed': true});
  Future<void> moveJoint(int joint, double degrees, int speed) async {
    if (!snapshot.canMove || profile?.hash != snapshot.profileHash) { throw StateError('Robot no disponible'); }
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

  Future<void> tcp(List<double> target, int speed, double gripper) async {
    final q = math!.plan(profile!.nativeValues, snapshot.joints, target, speed)
      ..[6] = gripper;
    if (!math!.path(profile!.nativeValues, snapshot.joints, q, speed)) {
      throw StateError('Trayectoria inválida');
    }
    await send('moveTcp', {
      'tcp': target,
      'speedPercent': speed,
      'gripperDegrees': gripper,
      'pauseMs': 0,
      'orientation': 'home',
    });
  }

  void teach(int speed, int pause) {
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
      ),
    );
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
    await repository!.saveProgram(name, body());
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
    subscription?.cancel();
    repository?.dispose();
    super.dispose();
  }
}
