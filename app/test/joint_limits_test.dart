import 'dart:convert';
import 'package:airobot/domain/models.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RobotViewModel vm;

  setUp(() async {
    final raw = await rootBundle.loadString('assets/profile.simulation.json');
    final profile = RobotProfile(
      raw,
      sha256.convert(utf8.encode(raw)).toString(),
    );
    vm = RobotViewModel()
      ..profile = profile
      ..snapshot = RobotSnapshot(
        connected: true,
        state: 'READY',
        reference: true,
        profileHash: profile.hash,
        joints: profile.home,
      );
  });
  tearDown(() => vm.dispose());

  testWidgets('Manual · Por servo shows the joint range gauge and limits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
    );
    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vel. máx'), findsOneWidget);
    expect(find.textContaining('Acel. máx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings shows tool offset and per-joint speed/accel summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
    );
    await tester.tap(find.byKey(const ValueKey('bottom-nav-4')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offset de herramienta'), findsOneWidget);
    expect(
      find.textContaining('Velocidad máx. por articulación'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Aceleración máx. por articulación'),
      findsOneWidget,
    );
  });
}
