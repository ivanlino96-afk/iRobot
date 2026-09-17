import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:airobot/presentation/design_tokens.dart';
import 'package:airobot/presentation/robot_view_model.dart';

void main() {
  test('RobotViewModel defaults to system theme and notifies on change', () {
    final vm = RobotViewModel();
    expect(vm.themeMode, ThemeMode.system);
    var notified = false;
    vm.addListener(() => notified = true);
    vm.setThemeMode(ThemeMode.dark);
    expect(vm.themeMode, ThemeMode.dark);
    expect(notified, true);
  });


  test('light and dark tokens keep the same alarm-color meaning', () {
    final light = airobotTheme().extension<AirobotTokens>()!;
    final dark = airobotTheme(
      brightness: Brightness.dark,
    ).extension<AirobotTokens>()!;
    expect(dark.danger, light.danger);
    expect(dark.warning, light.warning);
    expect(dark.success, light.success);
  });

  test('dark theme actually swaps the scaffold background', () {
    final light = airobotTheme();
    final dark = airobotTheme(brightness: Brightness.dark);
    expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));
    expect(dark.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp with ThemeMode.dark renders the dark scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: airobotTheme(),
        darkTheme: airobotTheme(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor ??
          Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
      airobotTheme(brightness: Brightness.dark).scaffoldBackgroundColor,
    );
  });
}
