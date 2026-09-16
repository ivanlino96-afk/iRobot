import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../domain/models.dart';
import '../infrastructure/api_client.dart';

class MqttRobotRepository implements RobotRepository {
  MqttRobotRepository(this.api, this.robotId, this.profile);
  final ApiClient api;
  final String robotId;
  RobotProfile? profile;
  final _states = StreamController<RobotSnapshot>.broadcast();
  @override
  Stream<RobotSnapshot> get states => _states.stream;
  MqttServerClient? client;
  RobotSnapshot snapshot = const RobotSnapshot();
  Map<String, dynamic>? session;
  int sequence = 0;
  Timer? timer;
  DateTime lastState = DateTime.fromMillisecondsSinceEpoch(0);
  bool renewing = false, closed = false;
  bool confirmed = false;
  final pending = <String, Completer<void>>{};
  StreamSubscription? subscription;
  String get base => 'airobot/v1/robots/$robotId/';
  String id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  // Initial broker access uses the bootId read from the API's authenticated status endpoint.
  Future<void> connect({String scope = 'control'}) async {
    final status = await api.get('/robots/$robotId/state');
    if (closed) throw StateError('Conexión cancelada');
    snapshot = RobotSnapshot.fromJson(Map<String, dynamic>.from(status));
    scope = ['ESTOP_LATCHED', 'FAULT'].contains(snapshot.state)
        ? 'recovery'
        : scope;
    session = Map<String, dynamic>.from(
      await api.post('/robots/$robotId/session', {
        'bootId': snapshot.bootId,
        'scope': scope,
      }),
    );
    if (closed) throw StateError('Conexión cancelada');
    sequence = 0;
    final mqtt = session!['mqtt'];
    final c = MqttServerClient.withPort(mqtt['host'], id(), mqtt['port']);
    c.secure = true;
    c.keepAlivePeriod = 10;
    c.autoReconnect = false;
    c.onDisconnected = _disconnected;
    client = c;
    await c.connect(mqtt['username'], mqtt['password']);
    if (closed) {
      c.disconnect();
      throw StateError('Conexión cancelada');
    }
    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('No fue posible conectar MQTT');
    }
    subscription = c.updates!.listen((events) {
      for (final event in events) {
        final message = event.payload as MqttPublishMessage;
        try {
          final raw = MqttPublishPayload.bytesToStringAsString(
            message.payload.message,
          );
          final m = jsonDecode(raw) as Map<String, dynamic>;
          if (event.topic == '${base}state') {
            final next = RobotSnapshot.fromJson(m);
            if (next.bootId != snapshot.bootId) {
              _disconnected();
              continue;
            }
            snapshot = next;
            lastState = DateTime.now();
            if (confirmed) _states.add(snapshot);
          } else if (event.topic == '${base}ack') {
            final completer = pending.remove(m['commandId']);
            if (completer != null) {
              if (m['status'] == 'accepted' ||
                  m['status'] == 'completed' ||
                  m['status'] == 'started' ||
                  m['status'] == 'duplicate' &&
                      m['reason'] == 'duplicate:accepted') {
                completer.complete();
              } else {
                completer.completeError(
                  StateError(m['reason'] ?? 'Orden rechazada'),
                );
              }
            }
          }
        } catch (e) {
          if (!closed) _states.add(snapshot.disconnected());
        }
      }
    });
    c.subscribe('${base}state', MqttQos.atLeastOnce);
    c.subscribe('${base}ack', MqttQos.atLeastOnce);
    await command('openSession', {});
    if (closed) throw StateError('Conexión cancelada');
    confirmed = true;
    lastState = DateTime.now();
    _states.add(snapshot);

    timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _heartbeat(),
    );
  }

  void _disconnected() {
    timer?.cancel();
    confirmed = false;
    snapshot = snapshot.disconnected();
    session = null;
    for (final p in pending.values) {
      if (!p.isCompleted) p.completeError(StateError('Conexión perdida'));
    }
    pending.clear();
    if (!closed) _states.add(snapshot.disconnected());
  }

  Future<void> _heartbeat() async {
    if (renewing || closed || session == null) return;
    renewing = true;
    try {
      if (DateTime.now().difference(lastState) > const Duration(seconds: 3) &&
          lastState.millisecondsSinceEpoch > 0) {
        _states.add(snapshot.disconnected());
        throw StateError('Telemetría vencida');
      }
      if ((session!['expiresAtEpochMs'] as int) -
              DateTime.now().millisecondsSinceEpoch <
          8000) {
        session = Map<String, dynamic>.from(
          await api.post('/robots/$robotId/session', {
            'bootId': snapshot.bootId,
            'sessionId': session!['sessionId'],
            'scope':
                snapshot.state == 'ESTOP_LATCHED' || snapshot.state == 'FAULT'
                ? 'recovery'
                : 'control',
          }),
        );
      }
      await command('heartbeat', {});
    } catch (_) {
      _disconnected();
      client?.disconnect();
    } finally {
      renewing = false;
    }
  }

  @override
  Future<void> command(String type, Map<String, dynamic> payload) async {
    final grant = session;
    if (grant == null ||
        client?.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('Conecta una sesión primero');
    }
    final commandId = id(), now = DateTime.now().millisecondsSinceEpoch;
    final data = {
      'schemaVersion': 1,
      'commandId': commandId,
      'robotId': robotId,
      'bootId': snapshot.bootId,
      'authorization': grant['authorization'],
      'controlSessionId': grant['sessionId'],
      'sequence': ++sequence,
      'createdAtEpochMs': now,
      'expiresAtEpochMs': now + 4000,
      'profileVersion': profile?.version ?? 0,
      'profileHash': profile?.hash ?? '',
      'kinematicsVersion': 'ik-dls-1',
      'type': type,
      'payload': payload,
    };
    final builder = MqttClientPayloadBuilder()..addString(jsonEncode(data));
    if (builder.payload!.length > 16384) {
      throw StateError('Orden demasiado grande');
    }
    final completer = Completer<void>();
    pending[commandId] = completer;
    client!.publishMessage(
      base +
          (type == 'emergencyStop'
              ? 'emergency'
              : type == 'activateProfile'
              ? 'config'
              : 'command'),
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: false,
    );
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      pending.remove(commandId);
    }
  }

  @override
  Future<void> activateProfile(RobotProfile p) async {
    await command('activateProfile', {
      'profileJson': p.raw,
      'profileHash': p.hash,
    });
    profile = p;
    timer?.cancel();
  }

  @override
  Future<List<Map<String, dynamic>>> programs() async =>
      (await api.get('/robots/$robotId/programs') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  @override
  Future<void> saveProgram(
    String name,
    Map<String, dynamic> body, {
    String? sourceId,
  }) async {
    await api.post('/robots/$robotId/programs', {
      'name': name,
      'body': body,
      'sourceId': ?sourceId,
    });
  }

  @override
  Future<void> deleteProgram(String id) async =>
      api.delete('/robots/$robotId/programs/$id');
  @override
  Future<void> dispose() async {
    closed = true;
    timer?.cancel();
    await subscription?.cancel();
    client?.disconnect();
    for (final p in pending.values) {
      if (!p.isCompleted) p.completeError(StateError('Sesión cerrada'));
    }
    pending.clear();
    await _states.close();
  }
}
