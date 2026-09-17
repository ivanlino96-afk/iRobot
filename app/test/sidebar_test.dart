import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/sidebar_menu.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Floating bottom nav navigates on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: airobotTheme(), home: const HomePage()),
    );
    expect(find.byKey(const ValueKey('bottom-nav-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('Por servo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sidebar expands and contracts without clipping controls', (
    tester,
  ) async {
    int selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: airobotTheme(),
        home: Scaffold(
          body: Row(
            children: [
              SidebarMenu(
                selectedIndex: 0,
                onSelected: (value) => selected = value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Contraer menú'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-2')));
    expect(selected, 2);
    await tester.tap(find.byTooltip('Expandir menú'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Invitado'), findsOneWidget);
    expect(find.text('Programas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
