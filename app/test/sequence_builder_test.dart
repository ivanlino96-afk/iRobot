import 'dart:async';
import 'dart:convert';
import 'package:airobot/domain/models.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/robot_view_model.dart';
import 'package:airobot/presentation/sequence_builder_screen.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class SeqFakeRepository implements RobotRepository {
  SeqFakeRepository(this.profile);
  final RobotProfile profile;
  final controller = StreamController<RobotSnapshot>.broadcast(sync: true);
  final saveNames = <String>[];
  final savedBodies = <Map<String, dynamic>>[];

  void emit(String state) => controller.add(
    RobotSnapshot(
      connected: true,
      state: state,
      reference: true,
      profileHash: profile.hash,
      joints: profile.home,
      tcp: const [1, 2, 3],
    ),
  );

  @override
  Stream<RobotSnapshot> get states => controller.stream;
  @override
  Future<void> command(String type, Map<String, dynamic> payload) async {}
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
  }) async {
    saveNames.add(name);
    savedBodies.add(body);
  }
}

Future<RobotProfile> loadTestProfile() async {
  final raw = await rootBundle.loadString('assets/profile.simulation.json');
  return RobotProfile(raw, sha256.convert(utf8.encode(raw)).toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Home entry points open the sequence name popup', () {
    late RobotViewModel vm;
    late RobotProfile profile;

    setUp(() async {
      profile = await loadTestProfile();
      vm = RobotViewModel()
        ..profile = profile
        ..repository = SeqFakeRepository(profile)
        ..snapshot = RobotSnapshot(
          connected: true,
          state: 'READY',
          reference: true,
          profileHash: profile.hash,
          joints: profile.home,
          tcp: const [0, 0, 0],
        );
    });
    tearDown(() => vm.dispose());

    testWidgets('Hero "Crear secuencia" button opens the name popup', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
      );
      await tester.tap(find.text('Crear secuencia'));
      await tester.pumpAndSettle();
      expect(find.text('Nombre de la secuencia'), findsOneWidget);
      expect(find.byType(SequenceBuilderScreen), findsNothing);

      await tester.enterText(find.byType(TextField), 'Mi secuencia');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.byType(SequenceBuilderScreen), findsOneWidget);
      expect(find.text('Mi secuencia'), findsWidgets);
    });

    testWidgets('FAB quick action opens the name popup', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
      );
      await tester.tap(find.byTooltip('Acciones rápidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Crear secuencia'));
      await tester.pumpAndSettle();
      expect(find.text('Nombre de la secuencia'), findsOneWidget);
      expect(find.byType(SequenceBuilderScreen), findsNothing);
    });

    testWidgets('Continuar stays disabled while the name is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: airobotTheme(), home: HomePage(model: vm)),
      );
      await tester.tap(find.text('Crear secuencia'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continuar'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('SequenceBuilderScreen', () {
    late RobotViewModel vm;
    late SeqFakeRepository repo;
    late RobotProfile profile;

    setUp(() async {
      profile = await loadTestProfile();
      vm = RobotViewModel()..profile = profile;
      repo = SeqFakeRepository(profile);
    });
    tearDown(() => vm.dispose());

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: airobotTheme(),
          home: SequenceBuilderScreen(vm: vm, sequenceName: 'Secuencia test'),
        ),
      );
    }

    testWidgets('X/Y/Z indicators always share the same row', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await vm.attach(repo);
      repo.emit('READY');
      await pumpScreen(tester);
      await tester.pump();

      final xTop = tester.getTopLeft(find.text('1.0')).dy;
      final yTop = tester.getTopLeft(find.text('2.0')).dy;
      final zTop = tester.getTopLeft(find.text('3.0')).dy;
      expect(xTop, yTop);
      expect(yTop, zTop);
    });

    testWidgets(
      'Guardar punto is disabled right after EXECUTING->READY and enables after the settle delay',
      (tester) async {
        await vm.attach(repo);
        repo.emit('EXECUTING');
        await pumpScreen(tester);
        await tester.pump();

        FilledButton saveButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Guardar punto'),
        );
        expect(saveButton().onPressed, isNull);
        expect(
          find.text('Esperando a que el movimiento se estabilice…'),
          findsOneWidget,
        );

        repo.emit('READY');
        await tester.pump();
        expect(saveButton().onPressed, isNull);

        await tester.pump(const Duration(milliseconds: 900));
        expect(saveButton().onPressed, isNotNull);
        expect(find.text('Listo para guardar el punto'), findsOneWidget);
      },
    );

    testWidgets('Saving a point suggests a default name that is editable', (
      tester,
    ) async {
      await vm.attach(repo);
      repo.emit('READY');
      await pumpScreen(tester);
      await tester.pump(const Duration(milliseconds: 900));

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Guardar punto'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar punto'));
      await tester.pumpAndSettle();
      expect(find.text('Punto 1'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Origen');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Guardar punto'),
        ),
      );
      await tester.pumpAndSettle();

      expect(vm.steps, hasLength(1));
      expect(vm.steps.first.name, 'Origen');
      expect(find.text('Origen'), findsOneWidget);
    });

    testWidgets('Edit, reorder and delete preserve/change point names', (
      tester,
    ) async {
      vm.steps.addAll([
        ProgramStep(
          tcp: const [1, 0, 0],
          gripper: 0,
          speed: 10,
          pauseMs: 0,
          name: 'Uno',
        ),
        ProgramStep(
          tcp: const [2, 0, 0],
          gripper: 0,
          speed: 10,
          pauseMs: 0,
          name: 'Dos',
        ),
      ]);
      await vm.attach(repo);
      repo.emit('READY');
      await pumpScreen(tester);
      await tester.pump();

      // Reorder: move the first point ("Uno") down.
      await tester.ensureVisible(
        find.widgetWithIcon(IconButton, Icons.arrow_downward_rounded).first,
      );
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.arrow_downward_rounded).first,
      );
      await tester.pump();
      expect(vm.steps.map((s) => s.name).toList(), ['Dos', 'Uno']);

      // Edit the now-first point ("Dos") and rename it.
      await tester.ensureVisible(find.byTooltip('Editar punto').first);
      await tester.tap(find.byTooltip('Editar punto').first);
      await tester.pumpAndSettle();
      final nameField = find.widgetWithText(TextField, 'Dos');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Dos renombrado');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(vm.steps.first.name, 'Dos renombrado');

      // Delete asks for confirmation before removing.
      await tester.ensureVisible(find.byTooltip('Eliminar punto').first);
      await tester.tap(find.byTooltip('Eliminar punto').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(vm.steps, hasLength(2));

      await tester.tap(find.byTooltip('Eliminar punto').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(vm.steps, hasLength(1));
      expect(vm.steps.first.name, 'Uno');
    });

    testWidgets(
      'Guardar secuencia saves named steps under the pre-supplied name, clears steps, and pops',
      (tester) async {
        vm.steps.addAll([
          ProgramStep(
            tcp: const [1, 0, 0],
            gripper: 0,
            speed: 10,
            pauseMs: 0,
            name: 'Uno',
          ),
        ]);
        await vm.attach(repo);
        repo.emit('READY');

        await tester.pumpWidget(
          MaterialApp(
            theme: airobotTheme(),
            home: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SequenceBuilderScreen(
                            vm: vm,
                            sequenceName: 'Secuencia guardable',
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Guardar secuencia'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar secuencia'));
        await tester.pumpAndSettle();

        expect(repo.saveNames, ['Secuencia guardable']);
        final steps = repo.savedBodies.single['steps'] as List;
        expect(steps.single['name'], 'Uno');
        expect(vm.steps, isEmpty);
        expect(find.byType(SequenceBuilderScreen), findsNothing);
        expect(find.text('open'), findsOneWidget);
      },
    );

    testWidgets('Leaving with unsaved points asks for confirmation', (
      tester,
    ) async {
      vm.steps.add(
        ProgramStep(tcp: const [1, 0, 0], gripper: 0, speed: 10, pauseMs: 0),
      );
      await vm.attach(repo);
      repo.emit('READY');

      await tester.pumpWidget(
        MaterialApp(
          theme: airobotTheme(),
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SequenceBuilderScreen(
                          vm: vm,
                          sequenceName: 'Secuencia sin guardar',
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final backButton = find.byTooltip('Back');
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar secuencia?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(SequenceBuilderScreen), findsOneWidget);
      expect(vm.steps, hasLength(1));

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(vm.steps, isEmpty);
      expect(find.byType(SequenceBuilderScreen), findsNothing);
    });
  });
}
