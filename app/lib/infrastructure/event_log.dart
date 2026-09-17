import 'package:flutter/foundation.dart';

class RobotEvent {
  RobotEvent(this.category, this.message, {this.detail})
    : at = DateTime.now();
  final DateTime at;
  final String category;
  final String message;
  final Map<String, dynamic>? detail;
}

/// In-memory ring buffer of connection/command/session events, used to power
/// a diagnostics view. Owned by [RobotViewModel] so it survives a
/// [MqttRobotRepository] being recreated across reconnects.
class RobotEventLog extends ChangeNotifier {
  RobotEventLog({this.capacity = 200});
  final int capacity;
  final _entries = <RobotEvent>[];

  List<RobotEvent> get entries => List.unmodifiable(_entries);

  void add(String category, String message, {Map<String, dynamic>? detail}) {
    _entries.add(RobotEvent(category, message, detail: detail));
    if (_entries.length > capacity) _entries.removeAt(0);
    notifyListeners();
  }
}
