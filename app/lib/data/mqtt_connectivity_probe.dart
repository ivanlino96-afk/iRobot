import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../infrastructure/api_client.dart';

enum ConnectivityProbeStage { pending, checking, passed, failed }

class ConnectivityProbeResult {
  const ConnectivityProbeResult({
    required this.api,
    required this.broker,
    required this.robot,
    required this.message,
  });

  factory ConnectivityProbeResult.idle() => const ConnectivityProbeResult(
    api: ConnectivityProbeStage.pending,
    broker: ConnectivityProbeStage.pending,
    robot: ConnectivityProbeStage.pending,
    message: 'La prueba no envía movimientos ni modifica la posición del robot.',
  );

  final ConnectivityProbeStage api;
  final ConnectivityProbeStage broker;
  final ConnectivityProbeStage robot;
  final String message;
}

/// Verifies the authenticated path API -> MQTTS broker -> ESP32 telemetry.
/// It never publishes a robot command.
class MqttConnectivityProbe {
  MqttConnectivityProbe(this.api, this.robotId);

  final ApiClient api;
  final String robotId;

  String _clientId() => 'probe-${List.generate(
    12,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join()}';

  Future<ConnectivityProbeResult> run({
    void Function(ConnectivityProbeResult result)? onUpdate,
  }) async {
    var apiStage = ConnectivityProbeStage.checking;
    var brokerStage = ConnectivityProbeStage.pending;
    var robotStage = ConnectivityProbeStage.pending;

    void update(String message) => onUpdate?.call(
      ConnectivityProbeResult(
        api: apiStage,
        broker: brokerStage,
        robot: robotStage,
        message: message,
      ),
    );

    update('Comprobando la sesión autorizada con la API…');
    Map<String, dynamic> status;
    Map<String, dynamic> session;
    try {
      status = Map<String, dynamic>.from(
        await api.get('/robots/$robotId/state'),
      );
      session = Map<String, dynamic>.from(
        await api.post('/robots/$robotId/session', {
          'bootId': status['bootId'],
          'scope': 'control',
        }),
      );
      apiStage = ConnectivityProbeStage.passed;
    } catch (_) {
      return ConnectivityProbeResult(
        api: ConnectivityProbeStage.failed,
        broker: ConnectivityProbeStage.pending,
        robot: ConnectivityProbeStage.pending,
        message: 'No fue posible obtener una sesión autorizada de la API.',
      );
    }

    final mqtt = session['mqtt'];
    if (mqtt is! Map) {
      return ConnectivityProbeResult(
        api: apiStage,
        broker: ConnectivityProbeStage.failed,
        robot: ConnectivityProbeStage.pending,
        message: 'La API no entregó una configuración MQTT válida.',
      );
    }
    final host = mqtt['host']?.toString();
    final port = int.tryParse(mqtt['port']?.toString() ?? '');
    final username = mqtt['username']?.toString();
    final password = mqtt['password']?.toString();
    if (host == null || port == null || username == null || password == null) {
      return ConnectivityProbeResult(
        api: apiStage,
        broker: ConnectivityProbeStage.failed,
        robot: ConnectivityProbeStage.pending,
        message: 'La API entregó credenciales MQTT incompletas.',
      );
    }

    brokerStage = ConnectivityProbeStage.checking;
    update('Comprobando TLS con el VPS…');
    final client = MqttServerClient.withPort(host, _clientId(), port)
      ..secure = true
      ..keepAlivePeriod = 10
      ..autoReconnect = false;
    StreamSubscription? subscription;
    try {
      await client.connect(username, password).timeout(const Duration(seconds: 10));
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError('MQTT connection rejected');
      }
      brokerStage = ConnectivityProbeStage.passed;
      robotStage = ConnectivityProbeStage.checking;
      update('TLS confirmado. Esperando telemetría del ESP32…');

      final telemetry = Completer<void>();
      final stateTopic = 'airobot/v1/robots/$robotId/state';
      subscription = client.updates?.listen((events) {
        for (final event in events) {
          if (event.topic != stateTopic) continue;
          try {
            final payload = event.payload as MqttPublishMessage;
            final raw = MqttPublishPayload.bytesToStringAsString(
              payload.payload.message,
            );
            final state = jsonDecode(raw);
            if (state is Map && state['bootId'] == status['bootId']) {
              telemetry.complete();
            }
          } catch (_) {
            // Ignore malformed telemetry; the robot has not confirmed yet.
          }
        }
      });
      client.subscribe(stateTopic, MqttQos.atLeastOnce);
      await telemetry.future.timeout(const Duration(seconds: 8));
      return ConnectivityProbeResult(
        api: apiStage,
        broker: brokerStage,
        robot: ConnectivityProbeStage.passed,
        message: 'Ruta completa confirmada: API, VPS seguro y ESP32 activos.',
      );
    } on TimeoutException {
      return ConnectivityProbeResult(
        api: apiStage,
        broker: brokerStage == ConnectivityProbeStage.checking
            ? ConnectivityProbeStage.failed
            : brokerStage,
        robot: brokerStage == ConnectivityProbeStage.passed
            ? ConnectivityProbeStage.failed
            : ConnectivityProbeStage.pending,
        message: brokerStage == ConnectivityProbeStage.passed
            ? 'El VPS respondió, pero no llegó telemetría del ESP32 en 8 segundos.'
            : 'El VPS no confirmó la conexión MQTT segura a tiempo.',
      );
    } catch (_) {
      return ConnectivityProbeResult(
        api: apiStage,
        broker: ConnectivityProbeStage.failed,
        robot: ConnectivityProbeStage.pending,
        message: 'No fue posible establecer MQTT seguro con el VPS.',
      );
    } finally {
      await subscription?.cancel();
      client.disconnect();
    }
  }
}
