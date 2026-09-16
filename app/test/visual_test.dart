import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/data/simulator_repository.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:airobot/presentation/robot_view_model.dart';

void main() {
  testWidgets('Five screens fit phone and tablet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = RobotViewModel();
    await tester.runAsync(() async {
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(icons))).load();
        final font = File('/System/Library/Fonts/SFNS.ttf');
        if (font.existsSync()) {
          final loader = FontLoader('.SF Pro Text')
            ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            );
          await loader.load();
        }
      }
      await vm.setSimulationMode(true);
      expect(vm.snapshot.connected, isTrue);
      expect(vm.snapshot.simulation, isTrue);
      expect(vm.canMove, isTrue);
      expect(vm.snapshot.tcp, isNotNull);
      await vm.act(vm.disarm);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(vm.snapshot.state, 'HOLD');
      expect(vm.canMove, isFalse);
      await vm.act(vm.arm);
      expect(vm.canMove, isTrue);
      await vm.moveJoint(0, 5, 10);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(vm.snapshot.joints[0], greaterThan(0));
      await vm.send('stop');
      // Freeze only the visual fixture, after exercising the real simulator.
      await vm.setSimulationMode(false);
      await vm.setSimulationMode(true);
      (vm.repository as SimulatorRepository).timer?.cancel();
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: airobotTheme(),
          debugShowCheckedModeBanner: false,
          home: HomePage(model: vm),
        ),
      ),
    );
    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
      final scroll = find.byType(SingleChildScrollView).first;
      await tester.drag(scroll, const Offset(0, 3000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../docs/previews')..createSync(recursive: true);
        File(
          '${dir.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pump(const Duration(milliseconds: 20));
    for (final label in [
      'Home',
      'Manual',
      'Programas',
      'Enseñar',
      'Configurar',
    ]) {
      await tester.tap(find.byType(DrawerButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final index = [
        'Home',
        'Manual',
        'Programas',
        'Enseñar',
        'Configurar',
      ].indexOf(label);
      await tester.tap(find.byKey(ValueKey('sidebar-$index')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: label);
      if (label == 'Manual') {
        for (final mode in ['Flechas', 'Coordenadas', 'Por servo']) {
          await tester.ensureVisible(find.text(mode));
          await tester.tap(find.text(mode));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: mode);
          await capture('Manual-$mode');
        }
      }
      await capture(label);
    }
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('sidebar-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final mode in ['Flechas', 'Coordenadas', 'Por servo']) {
      await tester.ensureVisible(find.text(mode));
      await tester.tap(find.text(mode));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'Tablet $mode');
    }
    await tester.runAsync(() async {
      await vm.setSimulationMode(false);
      expect(vm.snapshot.connected, isFalse);
      expect(vm.canMove, isFalse);
      expect(vm.repository, isNull);
      await vm.setSimulationMode(true);
      expect(vm.canMove, isTrue);
    });
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
}
