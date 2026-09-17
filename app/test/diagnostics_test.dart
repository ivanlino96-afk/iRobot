import 'package:airobot/data/mqtt_robot_repository.dart';
import 'package:airobot/infrastructure/api_client.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDiagnostics(WidgetTester tester, RobotViewModel vm) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
    );
    await tester.tap(find.byKey(const ValueKey('bottom-nav-5')));
    await tester.pumpAndSettle();
  }

  testWidgets('Shows a simulator notice when there is no MQTT repository', (
    tester,
  ) async {
    final vm = RobotViewModel();
    await pumpDiagnostics(tester, vm);
    expect(
      find.textContaining('Diagnóstico no aplica en modo simulador'),
      findsOneWidget,
    );
    vm.dispose();
  });

  testWidgets('Shows connection health once a MQTT repository is attached', (
    tester,
  ) async {
    final vm = RobotViewModel()
      ..repository = MqttRobotRepository(
        ApiClient('https://example.test'),
        'robot-1',
        null,
      );
    await pumpDiagnostics(tester, vm);
    expect(find.text('Sin sesión activa'), findsOneWidget);
    expect(
      find.text('Comandos pendientes de confirmación: 0'),
      findsOneWidget,
    );
    vm.dispose();
  });

  testWidgets('Renders logged events for a MQTT repository', (tester) async {
    final vm = RobotViewModel()
      ..repository = MqttRobotRepository(
        ApiClient('https://example.test'),
        'robot-1',
        null,
      );
    vm.eventLog.add('connection', 'Sesión de prueba');
    await pumpDiagnostics(tester, vm);
    expect(find.textContaining('Sesión de prueba'), findsOneWidget);
    vm.dispose();
  });
}
