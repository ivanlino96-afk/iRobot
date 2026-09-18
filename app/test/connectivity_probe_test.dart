import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the safe remote connectivity probe in settings', (
    tester,
  ) async {
    final vm = RobotViewModel();
    addTearDown(vm.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
    );
    await tester.tap(find.byKey(const ValueKey('bottom-nav-4')));
    await tester.pumpAndSettle();

    expect(find.text('Prueba de enlace remoto'), findsOneWidget);
    expect(find.textContaining('No envía movimientos'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.byKey(const ValueKey('run-connectivity-probe')),
      ).onPressed,
      isNull,
    );
  });
}
