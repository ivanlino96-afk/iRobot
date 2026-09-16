import 'dart:async';
import 'dart:convert';
import 'package:airobot/domain/models.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/jog_button.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/motion_popup.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:airobot_kinematics/airobot_kinematics.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ManualRepository implements RobotRepository {
  ManualRepository(this.profile);
  final RobotProfile profile;
  final controller = StreamController<RobotSnapshot>.broadcast(sync: true);
  final commands = <String>[];
  final payloads = <Map<String, dynamic>>[];
  bool acknowledgeOnly = false;
  void emit(String state, {bool connected = true}) => controller.add(
    RobotSnapshot(
      connected: connected,
      state: state,
      reference: true,
      profileHash: profile.hash,
      joints: profile.home,
      tcp: const [0, 0, 0],
    ),
  );
  @override
  Stream<RobotSnapshot> get states => controller.stream;
  @override
  Future<void> command(String type, Map<String, dynamic> payload) async {
    commands.add(type);
    payloads.add(payload);
    if (type == 'stop') emit('HOLD');
    if (type == 'emergencyStop') emit('ESTOP_LATCHED');
    if (['moveJoint', 'moveTcp', 'goHome', 'runProgram'].contains(type) &&
        !acknowledgeOnly) {
      emit('EXECUTING');
    }
  }

  @override
  Future<void> dispose() => controller.close();
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
  late ManualRepository repo;
  setUp(() async {
    final raw = await rootBundle.loadString('assets/profile.simulation.json');
    final profile = RobotProfile(
      raw,
      sha256.convert(utf8.encode(raw)).toString(),
    );
    vm = RobotViewModel()
      ..profile = profile
      ..math = NativeKinematics();
    repo = ManualRepository(profile);
    await vm.attach(repo);
    repo.emit('READY');
  });
  tearDown(() => vm.dispose());

  test('Stop cancels pending IK even while the action is busy', () async {
    final action = vm.act(
      () => vm.tcp([0, 0, 0], 10, 0, keepOrientation: true),
    );
    expect(vm.busy, isTrue);
    await vm.stopMotion();
    await action;
    expect(repo.commands, ['stop']);
    expect(vm.actionFailed, isTrue);
    expect(vm.motionStatus, 'Movimiento detenido');
  });
  test(
    'TCP retains current orientation and completion requires telemetry',
    () async {
      await vm.tcp([0, 0, 0], 10, 0, keepOrientation: true);
      expect(repo.payloads.single['orientation'], 'current');
      expect(vm.motionStatus, 'En movimiento');
      repo.emit('READY');
      expect(vm.motionStatus, 'Movimiento completado');
    },
  );
  test(
    'Held jog does not queue another target without execution telemetry',
    () async {
      repo.acknowledgeOnly = true;
      final hold = vm.holdJog(() => vm.jogGripper(6, 1, 10));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(repo.commands, ['moveJoint']);
      await vm.stopMotion();
      await hold;
      expect(repo.commands, ['moveJoint', 'stop']);
      expect(vm.holding, isFalse);
    },
  );
  test('Held jog repeats after completion and stops on disconnect', () async {
    final hold = vm.holdJog(() => vm.jogGripper(6, 1, 10));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    repo.emit('READY');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(repo.commands.where((c) => c == 'moveJoint').length, 2);
    repo.emit('UNKNOWN', connected: false);
    await hold;
    expect(vm.holding, isFalse);
    expect(repo.commands.where((c) => c == 'moveJoint').length, 2);
  });
  test('Manual input rejects nonfinite values and gripper limits', () async {
    expect(vm.coordinateError('NaN'), isNotNull);
    expect(vm.coordinateError('1,5'), isNull);
    expect(vm.coordinateError('999', gripper: true), isNotNull);
    await expectLater(vm.jogGripper(6, 999, 10), throwsStateError);
    expect(repo.commands, isEmpty);
  });
  testWidgets('A sustained gesture is stopped after ten seconds', (
    tester,
  ) async {
    repo.acknowledgeOnly = true;
    final hold = vm.holdJog(() => vm.jogGripper(6, 1, 10));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 100));
    await hold;
    expect(vm.holding, isFalse);
    expect(repo.commands, ['moveJoint', 'stop']);
  });
  testWidgets(
    'Home quick action opens a popup and emergency Stop bypasses busy',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: airobotTheme(),
          home: HomePage(model: vm),
        ),
      );
      await tester.tap(find.byTooltip('Acciones rápidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Ir a home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MotionPopup), findsOneWidget);
      expect(find.text('En movimiento'), findsWidgets);
      vm.busy = true;
      vm.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(repo.commands, ['goHome', 'emergencyStop']);
      expect(find.byType(MotionPopup), findsNothing);
      vm.busy = false;
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Popup closes on completed telemetry and stays on disconnect', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: airobotTheme(),
        home: HomePage(model: vm),
      ),
    );
    await vm.send('moveJoint', {'joint': 0, 'degrees': 1, 'speedPercent': 10});
    await tester.pump();
    expect(find.byType(MotionPopup), findsOneWidget);
    repo.emit('READY');
    await tester.pump();
    expect(find.byType(MotionPopup), findsNothing);
    await vm.send('moveJoint', {'joint': 0, 'degrees': 2, 'speedPercent': 10});
    repo.emit('UNKNOWN', connected: false);
    await tester.pump();
    expect(find.text('Estado sin confirmar'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Cerrar aviso'));
    await tester.pump();
    expect(find.byType(MotionPopup), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Jog supports a tap and releases a sustained gesture', (
    tester,
  ) async {
    var taps = 0, holds = 0, releases = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JogButton(
            label: 'X+',
            icon: Icons.arrow_forward,
            enabled: true,
            onStep: () => taps++,
            onHold: () => holds++,
            onRelease: () => releases++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('X+'));
    expect(taps, 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('X+')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(holds, 1);
    await gesture.up();
    await tester.pump();
    expect(releases, 1);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
