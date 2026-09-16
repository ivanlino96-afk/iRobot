import 'package:airobot/presentation/quick_actions.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Quick actions opens both actions and closes after selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var home = 0, sequences = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: airobotTheme(),
        home: Scaffold(
          floatingActionButton: QuickActions(
            onGoHome: () => home++,
            onCreateSequence: () => sequences++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Acciones rápidas'));
    await tester.pumpAndSettle();
    expect(find.text('Ir a home'), findsOneWidget);
    await tester.tap(find.text('Ir a home'));
    await tester.pumpAndSettle();
    expect(home, 1);
    expect(find.text('Ir a home'), findsNothing);
    await tester.tap(find.byTooltip('Acciones rápidas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear secuencia'));
    await tester.pumpAndSettle();
    expect(sequences, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Home is unavailable when robot cannot move', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: QuickActions(
            onGoHome: null,
            onCreateSequence: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Acciones rápidas'));
    await tester.pumpAndSettle();
    final button = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, 'Ir a home'),
    );
    expect(button.onPressed, isNull);
  });
}
