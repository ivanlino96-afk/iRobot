import 'dart:convert';
import 'package:airobot/domain/models.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements RobotRepository {
  FakeRepository();
  final commands = <String>[];
  final deletedIds = <String>[];
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
  Future<void> deleteProgram(String id) async {
    deletedIds.add(id);
  }

  @override
  Future<List<Map<String, dynamic>>> programs() async => [];
  @override
  Future<void> saveProgram(
    String name,
    Map<String, dynamic> body, {
    String? sourceId,
  }) async {}
}

Future<RobotProfile> loadTestProfile() async {
  final raw = await rootBundle.loadString('assets/profile.simulation.json');
  return RobotProfile(raw, sha256.convert(utf8.encode(raw)).toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Programs screen confirmations', () {
    late RobotViewModel vm;
    late FakeRepository repo;
    late RobotProfile profile;

    setUp(() async {
      profile = await loadTestProfile();
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
        )
        ..saved = [
          {
            'id': 'p1',
            'name': 'Secuencia A',
            'needsRevalidation': false,
            'body': {'steps': [], 'profileHash': profile.hash},
          },
        ];
    });
    tearDown(() => vm.dispose());

    Future<void> pumpPrograms(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-2')));
      await tester.pumpAndSettle();
    }

    testWidgets('Eliminar asks for confirmation and only deletes on confirm', (
      tester,
    ) async {
      await pumpPrograms(tester);
      await tester.tap(find.byTooltip('Eliminar programa'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar "Secuencia A"?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, isEmpty);
      expect(find.text('Secuencia A'), findsOneWidget);

      await tester.tap(find.byTooltip('Eliminar programa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['p1']);
    });

    testWidgets('Ejecutar asks for confirmation before running', (
      tester,
    ) async {
      await pumpPrograms(tester);
      await tester.tap(find.text('Ejecutar'));
      await tester.pumpAndSettle();
      expect(find.text('Ejecutar "Secuencia A"'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.commands, isEmpty);

      await tester.tap(find.text('Ejecutar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Ejecutar'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.commands, ['runProgram']);
    });
  });

  group('Teach step reordering and deletion', () {
    late RobotViewModel vm;

    setUp(() async {
      final profile = await loadTestProfile();
      vm = RobotViewModel()
        ..profile = profile
        ..repository = FakeRepository()
        ..snapshot = RobotSnapshot(
          connected: true,
          state: 'READY',
          reference: true,
          profileHash: profile.hash,
          joints: profile.home,
          tcp: const [0, 0, 0],
        );
      vm.steps.addAll([
        ProgramStep(tcp: const [1, 0, 0], gripper: 0, speed: 10, pauseMs: 0),
        ProgramStep(tcp: const [2, 0, 0], gripper: 0, speed: 10, pauseMs: 0),
        ProgramStep(tcp: const [3, 0, 0], gripper: 0, speed: 10, pauseMs: 0),
      ]);
    });
    tearDown(() => vm.dispose());

    Future<void> pumpTeach(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-3')));
      await tester.pumpAndSettle();
    }

    testWidgets('Bajar moves a step later and is disabled on the last step', (
      tester,
    ) async {
      await pumpTeach(tester);
      expect(
        vm.steps.map((s) => s.tcp[0]).toList(),
        [1.0, 2.0, 3.0],
      );
      final bajarButtons = find.widgetWithIcon(
        IconButton,
        Icons.arrow_downward_rounded,
      );
      await tester.ensureVisible(bajarButtons.first);
      await tester.tap(bajarButtons.first);
      await tester.pump();
      expect(vm.steps.map((s) => s.tcp[0]).toList(), [2.0, 1.0, 3.0]);

      await tester.ensureVisible(bajarButtons.last);
      final lastBajar = tester.widget<IconButton>(bajarButtons.last);
      expect(lastBajar.onPressed, isNull);
    });

    testWidgets('Deleting a step asks for confirmation', (tester) async {
      await pumpTeach(tester);
      await tester.ensureVisible(find.byTooltip('Eliminar paso').first);
      await tester.tap(find.byTooltip('Eliminar paso').first);
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar este paso?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(vm.steps.length, 3);

      await tester.tap(find.byTooltip('Eliminar paso').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(vm.steps.length, 2);
      expect(vm.steps.map((s) => s.tcp[0]).toList(), [2.0, 3.0]);
    });
  });
}
