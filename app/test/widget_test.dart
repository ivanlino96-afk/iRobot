import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/main.dart';

void main() {
  testWidgets(
    'Disconnected app has no enabled movement and navigation fits phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const AiRobotApp());
      expect(find.text('UNKNOWN'), findsOneWidget);
      expect(find.text('Explorar simulador'), findsOneWidget);
      await tester.tap(find.text('Mover TCP'));
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
