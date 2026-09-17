import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../domain/models.dart';
import '../infrastructure/api_client.dart';
import '../infrastructure/event_log.dart';

/// Exponential backoff starting at 500ms, doubling per attempt, capped at 30s.
Duration backoffDelay(int attempt) {
  final ms = 500 * pow(2, min(attempt, 6)).toInt();
  return Duration(milliseconds: min(ms, 30000));
}

class MqttRobotRepository implements RobotRepository {
  MqttRobotRepository(this.api, this.robotId, this.profile, {RobotEventLog? log})
    : log = log ?? RobotEventLog();
  final ApiClient api;
  final String robotId;
  RobotProfile? profile;
  final RobotEventLog log;
  final _states = StreamController<RobotSnapshot>.broadcast();
  @override
  Stream<RobotSnapshot> get states => _states.stream;
  MqttServerClient? client;
  RobotSnapshot snapshot = const RobotSnapshot();
  Map<String, dynamic>? session;
  int sequence = 0;
  Timer? timer;
  Timer? _reconnectTimer;
  int reconnectAttempt = 0;
  bool reconnecting = false;
  String? lastDisconnectReason;
  DateTime lastState = DateTime.fromMillisecondsSinceEpoch(0);
  bool renewing = false, closed = false;
  bool confirmed = false;
  final pending = <String, Completer<void>>{};
  StreamSubscription? subscription;
  String get base => 'airobot/v1/robots/$robotId/';
  Duration? get sessionTimeToLive {
    final expires = session?['expiresAtEpochMs'] as int?;
    if (expires == null) return null;
    return Duration(
      milliseconds: expires - DateTime.now().millisecondsSinceEpoch,
    );
  }

  String id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  // Initial broker access uses the bootId read from the API's authenticated status endpoint.
  Future<void> connect({String scope = 'control'}) => _openSession(scope);

  Future<void> _openSession(String scope) async {
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
    c.onDisconnected = () => _disconnected('mqtt-disconnected');
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
              _disconnected('boot-id-mismatch');
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
    reconnectAttempt = 0;
    reconnecting = false;
    lastDisconnectReason = null;
    log.add('connection', 'Sesión establecida');
    _states.add(snapshot);

    timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _heartbeat(),
    );
  }

  void _disconnected(String cause) {
    timer?.cancel();
    confirmed = false;
    snapshot = snapshot.disconnected();
    session = null;
    lastDisconnectReason = cause;
    for (final p in pending.values) {
      if (!p.isCompleted) p.completeError(StateError('Conexión perdida'));
    }
    pending.clear();
    if (closed) return;
    _states.add(snapshot.disconnected());
    log.add('connection', 'Desconectado', detail: {'cause': cause});
    if (cause == 'auth-failed') {
      log.add('reconnect', 'No se reintenta: se requieren credenciales nuevas');
      return;
    }
    reconnecting = true;
    final delay = backoffDelay(reconnectAttempt);
    log.add(
      'reconnect',
      'Reintentando en ${delay.inSeconds}s (intento ${reconnectAttempt + 1})',
      detail: {'attempt': reconnectAttempt + 1, 'delayMs': delay.inMilliseconds},
    );
    _reconnectTimer = Timer(delay, _attemptReconnect);
    reconnectAttempt++;
  }

  Future<void> _attemptReconnect() async {
    if (closed) return;
    try {
      await _openSession('control');
      log.add('reconnect', 'Reconexión exitosa');
    } catch (e) {
      if (closed) return;
      log.add('reconnect', 'Reintento fallido: $e');
      reconnecting = true;
      final delay = backoffDelay(reconnectAttempt);
      _reconnectTimer = Timer(delay, _attemptReconnect);
      reconnectAttempt++;
    }
  }

  Future<void> _heartbeat() async {
    if (renewing || closed || session == null) return;
    renewing = true;
    try {
      if (DateTime.now().difference(lastState) > const Duration(seconds: 3) &&
          lastState.millisecondsSinceEpoch > 0) {
        _states.add(snapshot.disconnected());
        throw StateError('stale-telemetry');
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
    } catch (e) {
      final cause = e is DioException && [401, 403].contains(e.response?.statusCode)
          ? 'auth-failed'
          : e is StateError && e.message == 'stale-telemetry'
          ? 'stale-telemetry'
          : 'heartbeat-failed';
      _disconnected(cause);
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
    _reconnectTimer?.cancel();
    await subscription?.cancel();
    client?.disconnect();
    for (final p in pending.values) {
      if (!p.isCompleted) p.completeError(StateError('Sesión cerrada'));
    }
    pending.clear();
    await _states.close();
  }
}
