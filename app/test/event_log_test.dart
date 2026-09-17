import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/infrastructure/event_log.dart';

void main() {
  test('keeps entries in order and notifies listeners', () {
    final log = RobotEventLog();
    var notifications = 0;
    log.addListener(() => notifications++);
    log.add('connection', 'Conectado');
    log.add('reconnect', 'Intento 1');
    expect(log.entries.map((e) => e.message).toList(), [
      'Conectado',
      'Intento 1',
    ]);
    expect(log.entries.map((e) => e.category).toList(), [
      'connection',
      'reconnect',
    ]);
    expect(notifications, 2);
  });

  test('caps the buffer, dropping the oldest entries first', () {
    final log = RobotEventLog(capacity: 3);
    for (var i = 0; i < 5; i++) {
      log.add('connection', 'evento $i');
    }
    expect(log.entries.length, 3);
    expect(log.entries.map((e) => e.message).toList(), [
      'evento 2',
      'evento 3',
      'evento 4',
    ]);
  });

  test('entries expose a detail map and a timestamp', () {
    final log = RobotEventLog();
    log.add('reconnect', 'Reintentando', detail: {'attempt': 2});
    final entry = log.entries.single;
    expect(entry.detail?['attempt'], 2);
    expect(entry.at, isNotNull);
  });
}
