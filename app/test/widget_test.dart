import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/main.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/domain/models.dart';

void main() {
  testWidgets(
    'Connection indicator distinguishes pending, success, failure and simulation',
    (tester) async {
      final vm = RobotViewModel();
      await tester.pumpWidget(MaterialApp(home: HomePage(model: vm)));
      expect(find.text('Conectar'), findsOneWidget);
      vm.connecting = true;
      vm.notifyListeners();
      await tester.pump();
      expect(find.text('Conectando…'), findsOneWidget);
      vm.connecting = false;
      vm.robotId = 'AR-1';
      vm.snapshot = const RobotSnapshot(connected: true);
      vm.notifyListeners();
      await tester.pump();
      expect(find.text('ESP32 conectado'), findsOneWidget);
      expect(vm.canMove, false);
      vm.snapshot = vm.snapshot.disconnected();
      vm.connectionError = 'ESP32 sin respuesta';
      vm.notifyListeners();
      await tester.pump();
      expect(find.text('Error de conexión'), findsOneWidget);
      vm.robotId = 'SIMULADOR';
      vm.snapshot = const RobotSnapshot(connected: true, simulation: true);
      vm.notifyListeners();
      await tester.pump();
      expect(find.text('Simulador'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
  testWidgets(
    'Disconnected app has no enabled movement and navigation fits phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const AiRobotApp());
      expect(find.text('UNKNOWN'), findsNothing);
      expect(find.text('Crear secuencia'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Coordenadas'));
      await tester.tap(find.text('Coordenadas'));
      await tester.pumpAndSettle();
      expect(find.text('Validar y mover'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Validar y mover'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
