import 'dart:async';
import 'dart:convert';
import 'package:airobot/domain/models.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/motion_popup.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements RobotRepository {
  final commands = <String>[];
  @override
  Stream<RobotSnapshot> get states => const Stream.empty();
  @override
  Future<void> command(String type, Map<String, dynamic> payload) async {
    commands.add(type);
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> activateProfile(RobotProfile profile) async {}
  @override
  Future<void> deleteProgram(String id) async {}
  @override
  Future<List<Map<String, dynamic>>> programs() async => [];
  @override
  Future<void> saveProgram(
    String name,
    Map<String, dynamic> body, {
    String? sourceId,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RobotViewModel vm;
  late FakeRepository repo;

  setUp(() async {
    final raw = await rootBundle.loadString('assets/profile.simulation.json');
    final profile = RobotProfile(
      raw,
      sha256.convert(utf8.encode(raw)).toString(),
    );
    repo = FakeRepository();
    vm = RobotViewModel()
      ..profile = profile
      ..repository = repo
      ..snapshot = RobotSnapshot(
        connected: true,
        state: 'READY',
        reference: true,
        profileHash: profile.hash,
        joints: profile.home,
      );
  });
  tearDown(() => vm.dispose());

  testWidgets('There is no persistent stop button while the robot is idle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
    );
    expect(find.widgetWithText(FilledButton, 'Parar'), findsNothing);
    expect(find.byType(MotionPopup), findsNothing);
  });

  testWidgets(
    'Sending a Home command opens the motion popup with Stop, from any screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
      );
      // Navigate away from Home first: the popup must appear regardless of
      // which screen triggered the movement.
      await tester.tap(find.text('Configurar'));
      await tester.pumpAndSettle();

      unawaited(vm.send('goHome', {'speedPercent': 10}));
      await tester.pump();
      expect(find.byType(MotionPopup), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(repo.commands, contains('emergencyStop'));
    },
  );
}
