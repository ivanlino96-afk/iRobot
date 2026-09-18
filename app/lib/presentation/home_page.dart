import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../data/mqtt_connectivity_probe.dart';
import '../data/mqtt_robot_repository.dart';
import 'robot_view_model.dart';
import 'sidebar_menu.dart';
import 'jog_button.dart';
import 'quick_actions.dart';
import 'motion_popup.dart';
import 'design_tokens.dart';
import 'safety_notice.dart';
import 'bottom_nav_bar.dart';
import 'sequence_builder_screen.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.model});
  final RobotViewModel? model;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final RobotViewModel vm;
  int page = 0, speed = 10, joint = 0, manualMode = 0;
  double linearStep = 5, angularStep = 5;
  bool keepOrientation = true;
  final coordinateForm = GlobalKey<FormState>();
  final angle = TextEditingController(text: '0'),
      px = TextEditingController(text: '0'),
      py = TextEditingController(text: '0'),
      pz = TextEditingController(text: '0'),
      grip = TextEditingController(text: '0'),
      pause = TextEditingController(text: '500'),
      programName = TextEditingController();
  late final TextEditingController robotNameController;
  @override
  void initState() {
    super.initState();
    vm = widget.model ?? RobotViewModel();
    robotNameController = TextEditingController(text: vm.robotName);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.model == null) vm.dispose();
    robotNameController.dispose();
    for (final c in [angle, px, py, pz, grip, pause, programName]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      vm.suspend();
    }
  }

  double value(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '.'));
    if (v == null || !v.isFinite) {
      throw const FormatException('Introduce un número válido');
    }
    return v;
  }

  int pauseValue() {
    final v = int.tryParse(pause.text);
    if (v == null || v < 0 || v > 600000) {
      throw const FormatException('Pausa de 0 a 600000 ms');
    }
    return v;
  }

  void notice(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: error ? 5 : 3),
        backgroundColor: error ? context.tokens.danger : context.tokens.ink,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  Future<void> run(Future<void> Function() fn, {String? success}) async {
    if (vm.busy || vm.holding) return;
    HapticFeedback.selectionClick();
    await vm.act(fn);
    if (mounted) {
      notice(
        vm.actionFailed ? vm.message : success ?? vm.message,
        error: vm.actionFailed,
      );
    }
  }

  void selectPage(int value) {
    if (page == value) return;
    if (vm.holding) stopManual();
    HapticFeedback.selectionClick();
    setState(() => page = value);
  }

  Future<void> stopManual() async {
    try {
      await vm.stopMotion();
    } catch (e) {
      notice('Parada sin confirmar: $e', error: true);
    }
  }

  Future<void> holdManual(Future<void> Function() step) async {
    try {
      await vm.holdJog(step);
    } catch (e) {
      notice('$e', error: true);
    }
  }

  void useCurrentCoordinates() {
    final tcp = vm.snapshot.tcp;
    if (tcp == null || !vm.snapshot.reference || !vm.snapshot.connected) return;
    setState(() {
      px.text = tcp[0].toStringAsFixed(2);
      py.text = tcp[1].toStringAsFixed(2);
      pz.text = tcp[2].toStringAsFixed(2);
      grip.text = vm.snapshot.joints[6].toStringAsFixed(1);
    });
    coordinateForm.currentState?.validate();
  }

  Widget field(String label, TextEditingController c, {double width = 140}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(labelText: label),
        ),
      );
  Widget card(Widget child) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x060f2340),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.tokens.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
  Widget axisCard({
    required String axisLabel,
    required String valueText,
    required Color accentColor,
  }) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: context.tokens.cardBorder, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff0f172a).withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Text(
              'EJE $axisLabel',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            child: Text(
              valueText,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: context.tokens.muted,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'mm',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: context.tokens.muted,
            ),
          ),
        ],
      ),
    ),
  );
  Widget title(String text, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: vm,
    builder: (context, _) => LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 800;
        return PopScope(
          canPop: !vm.motionPopupVisible,
          child: Stack(
            children: [
              Scaffold(
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.endFloat,
                floatingActionButton: Padding(
                  padding: EdgeInsets.only(bottom: wide ? 0 : 76),
                  child: QuickActions(
                    key: ValueKey('quick-actions-$page'),
                    onGoHome: vm.canMove
                        ? () => run(
                            () => vm.send('goHome', {'speedPercent': speed}),
                          )
                        : null,
                    onCreateSequence: addSequence,
                  ),
                ),
                appBar: AppBar(
                  title: Text(
                    page == 1 ? 'Manual' : 'AiRobot',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.7,
                    ),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: () => selectPage(4),
                      icon: Icon(
                        vm.snapshot.connected
                            ? Icons.sensors
                            : Icons.sensors_off,
                        color: vm.snapshot.connected
                            ? context.tokens.success
                            : vm.connectionError != null
                            ? context.tokens.danger
                            : null,
                        size: 18,
                      ),
                      label: Text(vm.connectionLabel),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide)
                            SidebarMenu(
                              selectedIndex: page,
                              onSelected: selectPage,
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              key: ValueKey(page),
                              padding: EdgeInsets.fromLTRB(
                                wide ? 28 : 16,
                                12,
                                wide ? 28 : 16,
                                wide ? 96 : 140,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 900,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (vm.busy)
                                        const LinearProgressIndicator(
                                          minHeight: 2,
                                        ),
                                      AnimatedSwitcher(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 220),
                                        switchInCurve: Curves.easeOutCubic,
                                        layoutBuilder: (current, previous) =>
                                            current ?? const SizedBox.shrink(),
                                        transitionBuilder: (child, animation) =>
                                            FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin: const Offset(0, .025),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            ),
                                        child: KeyedSubtree(
                                          key: ValueKey(page),
                                          child: switch (page) {
                                            0 => control(),
                                            1 => tcp(),
                                            2 => programs(),
                                            3 => teach(),
                                            4 => settings(),
                                            _ => diagnostics(),
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!wide)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    child: BottomNavBar(
                      selectedIndex: page,
                      onSelected: (index) {
                        if (vm.holding) stopManual();
                        selectPage(index);
                      },
                    ),
                  ),
                ),
              if (vm.motionPopupVisible)
                MotionPopup(
                  status: vm.motionStatus,
                  unconfirmed: vm.motionUnconfirmed,
                  stopping: vm.emergencyPending,
                  onStop: () async {
                    try {
                      await vm.emergencyStopMotion();
                    } catch (_) {
                      /* The popup displays the failure and permits retry. */
                    }
                  },
                  onDismiss: vm.dismissMotionNotice,
                ),
            ],
          ),
        );
      },
    ),
  );
  Widget control() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, Ivan',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bienvenido a AiRobot',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.tokens.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffc6e1f7), Color(0xffc8c6f6), Color(0xffe3e0f4)],
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.precision_manufacturing_outlined,
              size: 48,
              color: Color(0xff0d0d0d),
            ),
            const SizedBox(height: 18),
            Text(
              vm.robotName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w400,
                letterSpacing: -1.4,
                color: const Color(0xff0d0d0d),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mueve, enseña y crea secuencias.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Color(0xff0d0d0d)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: addSequence,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff0d0d0d),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Crear secuencia'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        vm.snapshot.simulation
            ? 'Posición simulada · mm'
            : 'Posición objetivo · mm',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          for (int axis = 0; axis < 3; axis++) ...[
            if (axis > 0) const SizedBox(width: 12),
            Expanded(
              child: axisCard(
                axisLabel: ['X', 'Y', 'Z'][axis],
                valueText:
                    vm.snapshot.connected &&
                        vm.snapshot.reference &&
                        vm.snapshot.tcp != null
                    ? vm.snapshot.tcp![axis].toStringAsFixed(1)
                    : '—',
                accentColor: [
                  context.tokens.axisX,
                  context.tokens.axisY,
                  context.tokens.axisZ,
                ][axis],
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: () => selectPage(1),
            icon: const Icon(Icons.open_with),
            label: const Text('Mover'),
          ),
          FilledButton.icon(
            onPressed: vm.canMove
                ? () => run(() => vm.send('goHome', {'speedPercent': speed}))
                : null,
            icon: const Icon(Icons.home_outlined),
            label: const Text('Home'),
          ),
          OutlinedButton.icon(
            onPressed: vm.canArm ? () => run(vm.arm) : null,
            icon: const Icon(Icons.lock_open),
            label: const Text('Armar'),
          ),
          OutlinedButton.icon(
            onPressed: vm.canDisarm ? () => run(vm.disarm) : null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Desarmar'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('Desarmar detiene el movimiento y mantiene la consigna.'),
      const SizedBox(height: 4),
      const SafetyNotice(),
      const SizedBox(height: 12),

      if (vm.repository == null)
        const Text(
          'El simulador funciona sin conectar hardware. Sus datos mecánicos son de prueba.',
        ),
    ],
  );
  Widget jointControls() {
    final min = vm.profile?.minimum[joint] ?? -80.0;
    final max = vm.profile?.maximum[joint] ?? 80.0;
    final target = (double.tryParse(angle.text) ?? vm.snapshot.joints[joint])
        .clamp(min, max);
    const names = [
      'Base',
      'Primer brazo',
      'Segundo brazo',
      'Cabeceo',
      'Alabeo',
      'Rotación de garra',
      'Apertura de garra',
    ];
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: context.tokens.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.tokens.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: joint,
                isExpanded: true,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: context.tokens.muted,
                  size: 22,
                ),
                borderRadius: BorderRadius.circular(16),
                dropdownColor: Theme.of(context).colorScheme.surface,
                elevation: 4,
                items: [
                  for (int j = 0; j < 7; j++)
                    DropdownMenuItem<int>(
                      value: j,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: joint == j
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : context.tokens.surfaceMuted,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'J${j + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: joint == j
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : context.tokens.muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              names[j],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: context.tokens.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      joint = v;
                      angle.text = vm.snapshot.joints[v].toStringAsFixed(1);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(names[joint], style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '${target.toStringAsFixed(1)}°',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          Text(
            'Objetivo · límites ${min.toStringAsFixed(0)}° a ${max.toStringAsFixed(0)}°',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          jointRangeGauge(
            min: min,
            max: max,
            target: target,
            actual: vm.snapshot.reference
                ? vm.snapshot.joints[joint]
                : null,
          ),
          Slider(
            value: target,
            min: min,
            max: max > min ? max : min + 1,
            onChanged: vm.canMove
                ? (v) => setState(() => angle.text = v.toStringAsFixed(1))
                : null,
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: vm.canMove
                    ? () => setState(
                        () => angle.text = (target - angularStep)
                            .clamp(min, max)
                            .toStringAsFixed(1),
                      )
                    : null,
                child: Text('−${angularStep.toStringAsFixed(0)}°'),
              ),
              OutlinedButton(
                onPressed: vm.canMove
                    ? () => setState(
                        () => angle.text = (target + angularStep)
                            .clamp(min, max)
                            .toStringAsFixed(1),
                      )
                    : null,
                child: Text('+${angularStep.toStringAsFixed(0)}°'),
              ),
              FilledButton.icon(
                onPressed: vm.canMove
                    ? () => run(() => vm.moveJoint(joint, target, speed))
                    : null,
                icon: const Icon(Icons.arrow_forward),
                label: Text('Mover J${joint + 1}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            vm.snapshot.reference
                ? 'Consigna: ${vm.snapshot.joints[joint].toStringAsFixed(1)}°'
                : 'Referencia pendiente',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (vm.profile != null)
            Text(
              'Vel. máx ${vm.profile!.velocity[joint].toStringAsFixed(0)}°/s · '
              'Acel. máx ${vm.profile!.acceleration[joint].toStringAsFixed(0)}°/s²',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.tokens.muted),
            ),
          if (joint == 1)
            const Text(
              'J2 coordina dos servos calibrados.',
              style: TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }

  /// Visualizes where [target] (and, if known, the confirmed [actual]
  /// position) sits within the joint's calibrated [min]/[max] range.
  Widget jointRangeGauge({
    required double min,
    required double max,
    required double target,
    double? actual,
  }) {
    final span = (max - min).abs() < 1e-6 ? 1.0 : max - min;
    double fractionOf(double value) => ((value - min) / span).clamp(0.0, 1.0);
    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: context.tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: context.tokens.cardBorder),
              ),
            ),
            Positioned(
              left:
                  fractionOf(target) * (constraints.maxWidth - 4).clamp(0, double.infinity),
              child: Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (actual != null)
              Positioned(
                left:
                    fractionOf(actual) * (constraints.maxWidth - 10).clamp(0, double.infinity),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: context.tokens.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget manualRecovery() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (['FAULT', 'ESTOP_LATCHED'].contains(vm.snapshot.state) &&
          vm.snapshot.reason.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: context.tokens.danger,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  vm.snapshot.reason,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.tokens.danger),
                ),
              ),
            ],
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (vm.canReference && !vm.snapshot.reference)
            FilledButton.icon(
              onPressed: reference,
              icon: const Icon(Icons.my_location),
              label: const Text('Confirmar referencia'),
            ),
          if (vm.canArm)
            FilledButton.icon(
              onPressed: () => run(vm.arm),
              icon: const Icon(Icons.lock_open),
              label: Text(
                vm.snapshot.state == 'HOLD' ? 'Reanudar control' : 'Armar',
              ),
            ),
          if (['FAULT', 'ESTOP_LATCHED'].contains(vm.snapshot.state))
            OutlinedButton.icon(
              onPressed: vm.busy ? null : () => run(vm.reset),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Rearmar bloqueo'),
            ),
          OutlinedButton.icon(
            onPressed: vm.canMove
                ? () => run(() => vm.send('goHome', {'speedPercent': speed}))
                : null,
            icon: const Icon(Icons.home_outlined),
            label: const Text('Ir a home'),
          ),
        ],
      ),
    ],
  );

  Widget stepSelector(
    String label,
    double selected,
    List<double> values,
    ValueChanged<double> change,
  ) => Row(
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      DropdownButton<double>(
        value: selected,
        underline: const SizedBox.shrink(),
        items: values
            .map(
              (v) =>
                  DropdownMenuItem(value: v, child: Text(v.toStringAsFixed(0))),
            )
            .toList(),
        onChanged: vm.holding ? null : (v) => setState(() => change(v!)),
      ),
    ],
  );

  Widget velocity() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(
        'Velocidad · $speed% de los límites calibrados',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Slider(
        value: speed.toDouble(),
        min: 1,
        max: 100,
        divisions: 99,
        label: '$speed%',
        onChanged: vm.holding ? null : (v) => setState(() => speed = v.round()),
      ),
    ],
  );
  Widget tcp() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        vm.snapshot.simulation
            ? 'Posición simulada'
            : 'Posición objetivo estimada',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int axis = 0; axis < 3; axis++)
              manualIndicator(
                ['X · mm', 'Y · mm', 'Z · mm'][axis],
                vm.snapshot.connected &&
                        vm.snapshot.reference &&
                        vm.snapshot.tcp != null
                    ? vm.snapshot.tcp![axis]
                    : null,
                width: (constraints.maxWidth - 20) / 3,
              ),
            manualIndicator(
              'Rotación J6 · °',
              vm.snapshot.connected && vm.snapshot.reference
                  ? vm.snapshot.joints[5]
                  : null,
              width: (constraints.maxWidth - 10) / 2,
            ),
            manualIndicator(
              'Apertura J7 · °',
              vm.snapshot.connected && vm.snapshot.reference
                  ? vm.snapshot.joints[6]
                  : null,
              width: (constraints.maxWidth - 10) / 2,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (vm.motionStatus.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            vm.motionStatus,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      manualRecovery(),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: const [
            ButtonSegment(value: 0, label: FittedBox(child: Text('Por servo'))),
            ButtonSegment(value: 1, label: FittedBox(child: Text('Flechas'))),
            ButtonSegment(
              value: 2,
              label: FittedBox(child: Text('Coordenadas')),
            ),
          ],
          selected: {manualMode},
          onSelectionChanged: (selection) {
            if (vm.holding) stopManual();
            if (selection.single == 2) useCurrentCoordinates();
            HapticFeedback.selectionClick();
            setState(() => manualMode = selection.single);
          },
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: Theme.of(context).colorScheme.primaryContainer),
            ),
            animationDuration: const Duration(milliseconds: 180),
          ),
        ),
      ),
      const SizedBox(height: 20),
      AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        layoutBuilder: (current, previous) =>
            current ?? const SizedBox.shrink(),
        child: KeyedSubtree(
          key: ValueKey(manualMode),
          child: switch (manualMode) {
            0 => jointControls(),
            1 => arrowControls(),
            _ => coordinateControls(),
          },
        ),
      ),
      const SizedBox(height: 16),
      card(
        Column(
          children: [
            velocity(),
            if (manualMode == 1)
              stepSelector('Paso lineal · mm', linearStep, [
                1,
                5,
                10,
              ], (v) => linearStep = v),
            if (manualMode != 2)
              stepSelector('Paso angular · °', angularStep, [
                1,
                5,
                10,
              ], (v) => angularStep = v),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const SizedBox(height: 12),
      const ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Ayuda de control'),
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'X/Y/Z se expresan en mm respecto a home. Los valores son consignas estimadas, no mediciones. J6 gira la garra y J7 controla su apertura. La trayectoria TCP es articular y no necesariamente recta. Mantener una flecha repite pasos durante un máximo de 10 s; al soltar se solicita la parada.',
            ),
          ),
        ],
      ),
    ],
  );

  Widget manualIndicator(
    String label,
    double? position, {
    required double width,
  }) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.tokens.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            position?.toStringAsFixed(1) ?? '—',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: position != null
                      ? context.tokens.ink
                      : context.tokens.muted,
                ),
          ),
        ),
      ],
    ),
  );

  Widget arrowControls() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Desplazamiento', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Pulsa un paso · Mantén para repetir',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              jogButton('Y+', Icons.arrow_upward, 1, linearStep),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  jogButton('X−', Icons.arrow_back, 0, -linearStep),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      Icons.control_camera,
                      color: context.tokens.muted,
                    ),
                  ),
                  jogButton('X+', Icons.arrow_forward, 0, linearStep),
                ],
              ),
              const SizedBox(height: 8),
              jogButton('Y−', Icons.arrow_downward, 1, -linearStep),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            jogButton('Subir Z+', Icons.vertical_align_top, 2, linearStep),
            jogButton('Bajar Z−', Icons.vertical_align_bottom, 2, -linearStep),
          ],
        ),
        const Divider(),
        Text('Garra', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            gripperButton('Girar −', Icons.rotate_left, 5, -angularStep),
            gripperButton('Girar +', Icons.rotate_right, 5, angularStep),
            gripperButton('Apertura −', Icons.remove, 6, -angularStep),
            gripperButton('Apertura +', Icons.add, 6, angularStep),
          ],
        ),
      ],
    ),
  );

  Widget jogButton(String label, IconData icon, int axis, double step) =>
      JogButton(
        label: label,
        icon: icon,
        enabled:
            (vm.canMove || vm.holding) &&
            vm.profile?.geometry == true &&
            vm.snapshot.tcp != null,
        onStep: () => run(() => vm.jogAxis(axis, step, speed)),
        onHold: () => holdManual(() => vm.jogAxis(axis, step, speed)),
        onRelease: stopManual,
      );

  Widget gripperButton(String label, IconData icon, int joint, double step) =>
      JogButton(
        label: label,
        icon: icon,
        enabled: vm.canMove || vm.holding,
        onStep: () => run(() => vm.jogGripper(joint, step, speed)),
        onHold: () => holdManual(() => vm.jogGripper(joint, step, speed)),
        onRelease: stopManual,
      );

  Widget _minimalInput({
    required String label,
    required String unit,
    required TextEditingController controller,
    required bool isGripper,
    required Color accentColor,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: context.tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.tokens.cardBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.tokens.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorStyle: const TextStyle(height: 0.8, fontSize: 10),
                  suffixText: unit,
                  suffixStyle: TextStyle(
                    fontSize: 11,
                    color: context.tokens.muted,
                  ),
                ),
                validator: (v) =>
                    vm.coordinateError(v ?? '', gripper: isGripper),
              ),
            ),
          ],
        ),
      );

  Widget coordinateControls() => card(
        Form(
          key: coordinateForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          'Destino TCP',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'XYZ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Usar posición actual',
                    onPressed: vm.snapshot.reference && vm.snapshot.connected
                        ? useCurrentCoordinates
                        : null,
                    icon: const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _minimalInput(
                      label: 'X',
                      unit: 'mm',
                      controller: px,
                      isGripper: false,
                      accentColor: context.tokens.axisX,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _minimalInput(
                      label: 'Y',
                      unit: 'mm',
                      controller: py,
                      isGripper: false,
                      accentColor: context.tokens.axisY,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _minimalInput(
                      label: 'Z',
                      unit: 'mm',
                      controller: pz,
                      isGripper: false,
                      accentColor: context.tokens.axisZ,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _minimalInput(
                      label: 'J7',
                      unit: '°',
                      controller: grip,
                      isGripper: true,
                      accentColor: context.tokens.axisGripper,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: context.tokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.tokens.cardBorder),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Conservar orientación',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.tokens.ink,
                        ),
                      ),
                      subtitle: Text(
                        keepOrientation
                            ? 'Mantiene la orientación actual de la garra'
                            : 'Usa la orientación de home',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.tokens.muted,
                        ),
                      ),
                      value: keepOrientation,
                      onChanged: (v) => setState(() => keepOrientation = v),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: vm.canMove && vm.profile?.geometry == true
                      ? () {
                          if (coordinateForm.currentState!.validate()) {
                            run(
                              () => vm.tcp(
                                [value(px), value(py), value(pz)],
                                speed,
                                value(grip),
                                keepOrientation: keepOrientation,
                              ),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Validar y mover'),
                ),
              ),
            ],
          ),
        ),
      );
  Widget indicatorCard(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: context.tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.tokens.cardBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.tokens.ink,
                letterSpacing: -.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );

  Widget teach() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Nueva secuencia',
        'Guarda posiciones objetivo, velocidad y pausas.',
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          indicatorCard(
            'Eje X',
            vm.snapshot.tcp != null
                ? '${vm.snapshot.tcp![0].toStringAsFixed(1)} mm'
                : '--',
            Icons.straighten_outlined,
          ),
          indicatorCard(
            'Eje Y',
            vm.snapshot.tcp != null
                ? '${vm.snapshot.tcp![1].toStringAsFixed(1)} mm'
                : '--',
            Icons.straighten_outlined,
          ),
          indicatorCard(
            'Eje Z',
            vm.snapshot.tcp != null
                ? '${vm.snapshot.tcp![2].toStringAsFixed(1)} mm'
                : '--',
            Icons.height_outlined,
          ),
          indicatorCard(
            'Gripper (Garra)',
            '${vm.snapshot.joints[6].toStringAsFixed(1)}°',
            Icons.back_hand_outlined,
          ),
        ],
      ),
      const SizedBox(height: 20),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                field('Pausa · ms', pause),
                FilledButton.icon(
                  onPressed: vm.snapshot.reference
                      ? () => run(
                          () async => vm.teach(speed, pauseValue()),
                          success: 'Punto añadido',
                        )
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Guardar punto actual'),
                ),
              ],
            ),
            velocity(),
            const SizedBox(height: 12),
            for (int i = 0; i < vm.steps.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text('${i + 1}'.padLeft(2, '0')),
                title: Text(
                  vm.steps[i].tcp.map((x) => x.toStringAsFixed(1)).join(' / '),
                ),
                subtitle: Text(
                  '${vm.steps[i].speed}% · ${vm.steps[i].pauseMs} ms · garra ${vm.steps[i].gripper}°',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Editar paso',
                      onPressed: () => editStep(i),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Subir',
                      onPressed: i > 0
                          ? () => setState(() {
                              final s = vm.steps.removeAt(i);
                              vm.steps.insert(i - 1, s);
                            })
                          : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    IconButton(
                      tooltip: 'Bajar',
                      onPressed: i < vm.steps.length - 1
                          ? () => setState(() {
                              final s = vm.steps.removeAt(i);
                              vm.steps.insert(i + 1, s);
                            })
                          : null,
                      icon: const Icon(Icons.arrow_downward_rounded),
                    ),
                    IconButton(
                      tooltip: 'Eliminar paso',
                      onPressed: () async {
                        if (await confirm(
                          '¿Eliminar este paso?',
                          'Se quitará de la secuencia. Esta acción no se puede deshacer.',
                          confirmLabel: 'Eliminar',
                          destructive: true,
                        )) {
                          setState(() => vm.steps.removeAt(i));
                        }
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            if (vm.steps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Sin puntos. Mueve el robot desde Manual y guarda su posición objetivo.',
                ),
              ),
            TextField(
              controller: programName,
              decoration: const InputDecoration(
                labelText: 'Nombre del programa',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: vm.steps.isNotEmpty && !vm.busy
                  ? () => run(
                      () => vm.save(programName.text),
                      success: 'Programa guardado',
                    )
                  : null,
              child: Text(
                vm.snapshot.simulation
                    ? 'Guardar en esta simulación'
                    : 'Guardar en la nube',
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget programs() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Programas', 'Secuencias guardadas para tu robot.'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: vm.repository != null ? addSequence : null,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Agregar secuencia'),
          ),
          OutlinedButton.icon(
            onPressed: vm.repository != null
                ? () => run(vm.loadPrograms, success: 'Programas actualizados')
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (vm.saved.isEmpty)
        card(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aún no hay programas. Abre Enseñar para crear el primero.',
            ),
          ),
        ),
      for (final p in vm.saved)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'], style: Theme.of(context).textTheme.titleLarge),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      p['needsRevalidation'] == true
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: p['needsRevalidation'] == true
                          ? context.tokens.warning
                          : context.tokens.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(p['body']['steps'] as List).length} puntos · ${p['needsRevalidation'] == true ? 'Requiere revalidación' : 'Perfil compatible'}',
                      style: TextStyle(
                        color: p['needsRevalidation'] == true
                            ? context.tokens.warning
                            : context.tokens.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: vm.canMove && p['needsRevalidation'] != true
                          ? () async {
                              if (await confirm(
                                'Ejecutar "${p['name']}"',
                                'El robot físico se moverá siguiendo esta secuencia guardada.',
                                confirmLabel: 'Ejecutar',
                              )) {
                                run(() => vm.run(p));
                              }
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Ejecutar'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        vm.editProgram(p);
                        programName.text = p['name'];
                        setState(() => page = 3);
                      },
                      child: const Text('Editar copia'),
                    ),
                    if (p['needsRevalidation'] == true)
                      OutlinedButton(
                        onPressed: vm.snapshot.reference
                            ? () => confirmRevalidation(p)
                            : null,
                        child: const Text('Revalidar revisión'),
                      ),
                    IconButton(
                      tooltip: 'Eliminar programa',
                      onPressed: () async {
                        if (await confirm(
                          '¿Eliminar "${p['name']}"?',
                          'Esta acción no se puede deshacer.',
                          confirmLabel: 'Eliminar',
                          destructive: true,
                        )) {
                          run(() async {
                            await vm.repository!.deleteProgram(p['id']);
                            await vm.loadPrograms();
                          });
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Configuración', 'Robot, simulación y calibración'),
      if (vm.simulationMode)
        TextButton.icon(
          onPressed: () => run(() => vm.send('disconnectTest')),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Probar pérdida de control'),
        ),
      card(
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo desarrollador · Simulación'),
            subtitle: const Text(
              'Prueba la app con un robot virtual. Los programas son temporales. Al apagarlo se desconecta.',
            ),
            value: vm.simulationMode,
            onChanged: vm.busy || vm.connecting
                ? null
                : (enabled) async {
                    if (!enabled &&
                        (vm.steps.isNotEmpty || vm.saved.isNotEmpty) &&
                        !await confirm(
                          'Salir de la simulación',
                          'Los programas y pasos del simulador no se guardan de forma permanente; se perderán al desconectar.',
                          confirmLabel: 'Salir de todos modos',
                          destructive: true,
                        )) {
                      return;
                    }
                    run(
                      () => vm.setSimulationMode(enabled),
                      success: enabled
                          ? 'Simulador conectado'
                          : 'Simulador desconectado',
                    );
                  },
          ),
        ),
      ),
      const SizedBox(height: 16),
      remoteConnectivityProbe(),
      const SizedBox(height: 16),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nombre del robot',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Identifica tu robot en Home.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                field('Nombre del robot', robotNameController, width: 220),
                FilledButton.icon(
                  onPressed: () {
                    vm.setRobotName(robotNameController.text);
                    notice('Nombre del robot actualizado');
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar nombre'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vm.profile == null
                  ? 'Sin perfil activo'
                  : 'Perfil v${vm.profile!.version}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              vm.profile?.calibrated == true
                  ? 'Calibración declarada en el perfil'
                  : 'Calibración pendiente',
            ),
            Text(
              vm.profile?.geometry == true
                  ? 'Geometría validada'
                  : 'Geometría pendiente',
            ),
            if (vm.profile != null) ...[
              const SizedBox(height: 12),
              Text(
                'Offset de herramienta (tool): '
                '${vm.profile!.tool.map((v) => v.toStringAsFixed(0)).join(' / ')} mm',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Velocidad máx. por articulación: '
                '${vm.profile!.velocity.map((v) => v.toStringAsFixed(0)).join(' / ')}°/s',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Aceleración máx. por articulación: '
                '${vm.profile!.acceleration.map((v) => v.toStringAsFixed(0)).join(' / ')}°/s²',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: vm.repository != null ? profileEditor : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar perfil mecánico'),
            ),
            const SizedBox(height: 20),
            if (vm.profile != null)
              for (final s in vm.profile!.json['servos'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Canal ${s['pcaChannel']} → J${s['joint'] + 1} · ${s['min']}–${s['max']}° · offset ${s['offset']}°',
                  ),
                ),
            const Divider(),
            const Text(
              'Calibración individual: procedimiento por USB, con el brazo soportado. Consulta la guía de instalación y pruebas.',
            ),
            const SizedBox(height: 12),
            const SafetyNotice(),
          ],
        ),
      ),
    ],
  );

  Widget remoteConnectivityProbe() {
    final result = vm.connectivityProbe;
    final selectedRobot = vm.selectedProbeRobotId;
    final canTest =
        vm.api != null && selectedRobot != null && !vm.busy && !vm.connecting;
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prueba de enlace remoto',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Comprueba API → VPS con TLS → telemetría ESP32. No envía movimientos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (vm.robots.isNotEmpty)
            DropdownButtonFormField<String>(
              key: const ValueKey('connectivity-probe-robot'),
              initialValue: selectedRobot,
              decoration: const InputDecoration(labelText: 'Robot a comprobar'),
              items: vm.robots
                  .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                  .toList(),
              onChanged: vm.connectivityProbeRunning
                  ? null
                  : vm.selectProbeRobot,
            )
          else if (vm.api == null)
            OutlinedButton.icon(
              key: const ValueKey('open-login'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LoginPage(vm: vm)),
              ),
              icon: const Icon(Icons.login),
              label: const Text('Iniciar sesión'),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('open-pair'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _PairRobotDialog(vm: vm),
              ),
              icon: const Icon(Icons.qr_code_2_outlined),
              label: const Text('Emparejar robot'),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              probeStage('1 · API', result.api),
              probeStage('2 · VPS / TLS', result.broker),
              probeStage('3 · ESP32', result.robot),
            ],
          ),
          const SizedBox(height: 14),
          Text(result.message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('run-connectivity-probe'),
            onPressed: canTest && !vm.connectivityProbeRunning
                ? vm.testRemoteConnectivity
                : null,
            icon: vm.connectivityProbeRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check_outlined),
            label: Text(
              vm.connectivityProbeRunning
                  ? 'Comprobando enlace…'
                  : 'Probar enlace seguro',
            ),
          ),
        ],
      ),
    );
  }

  Widget probeStage(String label, ConnectivityProbeStage stage) {
    final (IconData icon, Color color) = switch (stage) {
      ConnectivityProbeStage.passed => (Icons.check_circle_outline, Colors.green),
      ConnectivityProbeStage.failed => (Icons.error_outline, context.tokens.danger),
      ConnectivityProbeStage.checking => (
          Icons.sync_outlined,
          Theme.of(context).colorScheme.primary,
        ),
      ConnectivityProbeStage.pending => (Icons.circle_outlined, context.tokens.muted),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
    );
  }

  Widget diagnostics() {
    final repo = vm.repository;
    if (repo is! MqttRobotRepository) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Diagnóstico', 'Salud de la conexión con el robot.'),
          card(
            const Text(
              'Diagnóstico no aplica en modo simulador: no hay sesión MQTT ni telemetría de red que inspeccionar.',
            ),
          ),
        ],
      );
    }
    final telemetryAge = DateTime.now().difference(repo.lastState);
    final ttl = repo.sessionTimeToLive;
    return AnimatedBuilder(
      animation: vm.eventLog,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Diagnóstico', 'Salud de la conexión con el robot.'),
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado de la sesión',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  repo.confirmed
                      ? 'Última telemetría: hace ${telemetryAge.inSeconds}s'
                      : 'Sin sesión activa',
                ),
                if (ttl != null)
                  Text(
                    ttl.isNegative
                        ? 'Sesión vencida, renovando…'
                        : 'Sesión expira en ${ttl.inSeconds}s',
                  ),
                Text('Comandos pendientes de confirmación: ${repo.pending.length}'),
                if (vm.reconnecting)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.tokens.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Reconectando… (intento ${vm.reconnectAttempt})',
                          style: TextStyle(color: context.tokens.warning),
                        ),
                      ],
                    ),
                  ),
                if (vm.lastDisconnectReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Última causa de desconexión: ${vm.lastDisconnectReason}',
                      style: TextStyle(color: context.tokens.muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Registro de eventos',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (vm.eventLog.entries.isEmpty)
            card(const Text('Sin eventos todavía.'))
          else
            card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in vm.eventLog.entries.reversed.take(50))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${e.at.toIso8601String().substring(11, 19)} · ${e.category} · ${e.message}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> reference() async {
    final home = List.generate(
      7,
      (i) => vm.snapshot.simulation ? vm.profile?.home[i].toString() ?? '' : '',
    );
    await showDialog(
      context: context,
      builder: (_) => _ReferenceDialog(
        home: home,
        onConfirm: (build) => run(() async => vm.reference(build())),
      ),
    );
  }

  Future<void> profileEditor() async {
    final editor = TextEditingController(
      text: vm.profile == null
          ? '{}'
          : const JsonEncoder.withIndent('  ').convert(vm.profile!.json),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perfil mecánico versionado'),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Incrementa version para activar cambios. Los programas anteriores requieren revalidación. No marques calibrado sin completar las pruebas.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: editor,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(labelText: 'Perfil JSON'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final raw = editor.text;
              Navigator.pop(ctx);
              run(() => vm.applyProfile(raw));
            },
            child: const Text('Validar y activar'),
          ),
        ],
      ),
    );
    editor.dispose();
  }

  Future<void> addSequence() async {
    if (vm.steps.isNotEmpty) {
      final discard = await confirm(
        '¿Descartar puntos sin guardar?',
        'Hay ${vm.steps.length} punto(s) de una sesión anterior sin guardar. Empezar una secuencia nueva los descartará.',
        confirmLabel: 'Descartar y continuar',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SequenceNameDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    vm.discardSteps();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SequenceBuilderScreen(vm: vm, sequenceName: name),
      ),
    );
  }

  Future<bool> confirm(
    String title,
    String body, {
    String confirmLabel = 'Confirmar',
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: context.tokens.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> confirmRevalidation(Map<String, dynamic> p) async {
    if (await confirm(
      'Revalidar con el perfil actual',
      'Los mismos puntos pueden producir movimientos distintos tras cambiar home o geometría. Se validarán de nuevo y se guardará una revisión; no se ejecutará.',
      confirmLabel: 'Confirmar revalidación',
    )) {
      run(() => vm.revalidate(p));
    }
  }

  Future<void> editStep(int i) async {
    final controllers = [
      for (final v in [
        ...vm.steps[i].tcp,
        vm.steps[i].gripper,
        vm.steps[i].speed,
        vm.steps[i].pauseMs,
      ])
        TextEditingController(text: '$v'),
    ];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar punto ${i + 1}'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (int j = 0; j < 6; j++)
                field(
                  [
                    'X mm',
                    'Y mm',
                    'Z mm',
                    'Garra °',
                    'Velocidad %',
                    'Pausa ms',
                  ][j],
                  controllers[j],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              run(() async {
                final vals = controllers.map(value).toList();
                if (vals[4] != vals[4].roundToDouble() ||
                    vals[5] != vals[5].roundToDouble()) {
                  throw const FormatException(
                    'Velocidad y pausa deben ser enteros',
                  );
                }
                vm.steps[i] = ProgramStep(
                  tcp: vals.take(3).toList(),
                  gripper: vals[3],
                  speed: vals[4].toInt(),
                  pauseMs: vals[5].toInt(),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
  }
}

// Owns its TextEditingController via normal widget lifecycle (disposed only
// once the dialog is actually unmounted) instead of disposing it right after
// showDialog's future resolves, which races the dialog's closing transition
// and crashes when the autofocused field loses focus mid-animation.
// Same rationale as _SequenceNameDialog: owns its TextEditingControllers via
// normal widget lifecycle instead of disposing them right after showDialog's
// future resolves, which races the dialog's closing transition and crashes
// (disposed TextEditingController used mid-animation).
class _ReferenceDialog extends StatefulWidget {
  const _ReferenceDialog({required this.home, required this.onConfirm});

  final List<String> home;
  final void Function(List<double> Function() build) onConfirm;

  @override
  State<_ReferenceDialog> createState() => _ReferenceDialogState();
}

class _ReferenceDialogState extends State<_ReferenceDialog> {
  late final controllers = [
    for (final text in widget.home) TextEditingController(text: text),
  ];

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<double> _build() => [
    for (final c in controllers)
      double.tryParse(c.text.replaceAll(',', '.')) ??
          (throw const FormatException('Introduce un número válido')),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirmar referencia'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Introduce los ángulos del montaje observado. Registrar la referencia no mueve el brazo ni mide su posición.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (int i = 0; i < controllers.length; i++)
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: controllers[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: 'J${i + 1} · °'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          widget.onConfirm(_build);
          Navigator.pop(context);
        },
        child: const Text('Confirmar ángulos'),
      ),
    ],
  );
}

class _SequenceNameDialog extends StatefulWidget {
  const _SequenceNameDialog();

  @override
  State<_SequenceNameDialog> createState() => _SequenceNameDialogState();
}

class _SequenceNameDialogState extends State<_SequenceNameDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nombre de la secuencia'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Nombre'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Continuar'),
      ),
    ],
  );
}

class _PairRobotDialog extends StatefulWidget {
  const _PairRobotDialog({required this.vm});
  final RobotViewModel vm;

  @override
  State<_PairRobotDialog> createState() => _PairRobotDialogState();
}

class _PairRobotDialogState extends State<_PairRobotDialog> {
  final controller = TextEditingController();
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.vm.pair(controller.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = 'No se pudo emparejar: $e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Emparejar robot'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pega aquí el contenido de pairing.json.'),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '{"robotId":"AR-001","token":"..."}',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: submitting || controller.text.trim().isEmpty
            ? null
            : submit,
        child: submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Emparejar'),
      ),
    ],
  );
}
