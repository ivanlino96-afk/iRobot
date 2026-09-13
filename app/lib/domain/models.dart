import 'dart:convert';
import 'package:crypto/crypto.dart';

class RobotProfile {
  RobotProfile(this.raw, this.hash) {
    if (sha256.convert(utf8.encode(raw)).toString() != hash) {
      throw const FormatException('Hash de perfil incorrecto');
    }
    json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['kinematicsVersion'] != 'ik-dls-1') {
      throw const FormatException('Versión de cinemática no soportada');
    }
    nativeValues = _flatten();
  }
  final String raw, hash;
  late final Map<String, dynamic> json;
  late final List<double> nativeValues;
  int get version => json['version'] as int;
  List<double> get home => numbers(json['home'], 7);
  bool get calibrated => json['calibrated'] == true;
  bool get geometry => json['geometryValidated'] == true;
  static List<double> numbers(dynamic value, int length) {
    if (value is! List ||
        value.length != length ||
        value.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('Valores numéricos inválidos');
    }
    return value.map<double>((v) => (v as num).toDouble()).toList();
  }

  List<double> _flatten() {
    final p = json;
    if (p['servos'] is! List ||
        p['servos'].length != 8 ||
        p['axes'] is! List ||
        p['axes'].length != 6 ||
        p['boxes'] is! List ||
        p['boxes'].length > 8) {
      throw const FormatException('Estructura de perfil inválida');
    }
    return [
      calibrated ? 1 : 0,
      geometry ? 1 : 0,
      (p['linkRadius'] as num).toDouble(),
      for (final k in [
        'minimum',
        'maximum',
        'home',
        'velocity',
        'acceleration',
      ])
        ...numbers(p[k], 7),
      for (final s in p['servos'])
        ...numbers([
          s['joint'],
          s['pcaChannel'],
          s['zero'],
          s['offset'],
          s['ratio'],
          s['min'],
          s['max'],
          s['pulseMin'],
          s['pulseMax'],
        ], 9),
      for (final a in p['axes']) ...[
        ...numbers(a['origin'], 3),
        ...numbers(a['axis'], 3),
      ],
      ...numbers(p['tool'], 3),
      (p['boxes'] as List).length.toDouble(),
      for (final b in p['boxes']) ...[
        ...numbers(b['min'], 3),
        ...numbers(b['max'], 3),
      ],
    ];
  }
}

class RobotSnapshot {
  const RobotSnapshot({
    this.connected = false,
    this.state = 'UNKNOWN',
    this.reason = '',
    this.bootId = '',
    this.joints = const [0, 0, 0, 0, 0, 0, 0],
    this.tcp,
    this.reference = false,
    this.simulation = false,
    this.profileHash = '',
    this.latchId = '',
    this.resetNonce = '',
  });
  final bool connected, reference, simulation;
  final String state, reason, bootId, profileHash, latchId, resetNonce;
  final List<double> joints;
  final List<double>? tcp;
  factory RobotSnapshot.fromJson(Map<String, dynamic> m) => RobotSnapshot(
    connected: true,
    state: m['state'] ?? 'UNKNOWN',
    reason: m['reason'] ?? '',
    bootId: m['bootId'] ?? '',
    joints: RobotProfile.numbers(m['targetJointDegrees'], 7),
    tcp: m['estimatedTcpMm'] == null
        ? null
        : RobotProfile.numbers(m['estimatedTcpMm'], 3),
    reference: m['referenceValid'] == true,
    simulation: m['simulation'] == true,
    profileHash: m['profileHash'] ?? '',
    latchId: m['latchId'] ?? '',
    resetNonce: m['resetNonce'] ?? '',
  );
  RobotSnapshot disconnected() => RobotSnapshot(
    state: 'UNKNOWN',
    reason: 'Sin telemetría reciente',
    bootId: bootId,
    joints: joints,
    simulation: simulation,
    profileHash: profileHash,
  );
  bool get canMove => connected && state == 'READY' && reference;
}

class ProgramStep {
  ProgramStep({
    required this.tcp,
    required this.gripper,
    required this.speed,
    required this.pauseMs,
  }) {
    if (tcp.length != 3 ||
        tcp.any((x) => !x.isFinite) ||
        !gripper.isFinite ||
        speed < 1 ||
        speed > 100 ||
        pauseMs < 0 ||
        pauseMs > 600000) {
      throw const FormatException('Paso inválido');
    }
  }
  final List<double> tcp;
  final double gripper;
  final int speed, pauseMs;
  Map<String, dynamic> toJson() => {
    'tcp': tcp,
    'gripperDegrees': gripper,
    'speedPercent': speed,
    'pauseMs': pauseMs,
  };
  factory ProgramStep.fromJson(Map<String, dynamic> j) => ProgramStep(
    tcp: RobotProfile.numbers(j['tcp'], 3),
    gripper: (j['gripperDegrees'] as num).toDouble(),
    speed: j['speedPercent'] as int,
    pauseMs: j['pauseMs'] as int,
  );
}

abstract class RobotRepository {
  Stream<RobotSnapshot> get states;
  Future<void> command(String type, Map<String, dynamic> payload);
  Future<void> activateProfile(RobotProfile profile);
  Future<List<Map<String, dynamic>>> programs();
  Future<void> saveProgram(String name, Map<String, dynamic> body);
  Future<void> deleteProgram(String id);
  Future<void> dispose();
}
