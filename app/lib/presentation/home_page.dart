import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'robot_view_model.dart';
import 'sidebar_menu.dart';
import 'jog_button.dart';
import 'quick_actions.dart';
import 'motion_popup.dart';

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
        backgroundColor: error
            ? const Color(0xffb4233c)
            : const Color(0xff17233b),
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
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xffe7ebf3)),
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
      color: Colors.white,
      border: Border.all(color: const Color(0xffe7ebf3), width: 1.5),
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
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: Color(0xff9ca3af),
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'mm',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xff94a3b8),
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
                floatingActionButton: QuickActions(
                  key: ValueKey('quick-actions-$page'),
                  onGoHome: vm.canMove
                      ? () => run(
                          () => vm.send('goHome', {'speedPercent': speed}),
                        )
                      : null,
                  onCreateSequence: () => selectPage(3),
                ),
                onDrawerChanged: (open) {
                  if (open && vm.holding) stopManual();
                },
                drawer: wide
                    ? null
                    : Drawer(
                        width: 280,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        child: Builder(
                          builder: (drawerContext) => SidebarMenu(
                            selectedIndex: page,
                            onClose: () => Navigator.pop(drawerContext),
                            onSelected: (index) {
                              Navigator.pop(drawerContext);
                              selectPage(index);
                            },
                          ),
                        ),
                      ),
                appBar: AppBar(
                  leading: wide
                      ? null
                      : Builder(
                          builder: (context) => DrawerButton(
                            onPressed: () {
                              if (vm.holding) stopManual();
                              Scaffold.of(context).openDrawer();
                            },
                          ),
                        ),
                  title: Text(
                    page == 1 ? 'Manual' : 'AiRobot',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.7,
                    ),
                  ),
                  actions: [
                    if (page == 1)
                      OutlinedButton.icon(
                        onPressed: vm.snapshot.connected ? stopManual : null,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text('Parar'),
                      ),
                    if (page != 1)
                      TextButton.icon(
                        onPressed: () => selectPage(4),
                        icon: Icon(
                          vm.snapshot.connected
                              ? Icons.sensors
                              : Icons.sensors_off,
                          color: vm.snapshot.connected
                              ? Colors.green
                              : vm.connectionError != null
                              ? Colors.red
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
                                96,
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
                                            _ => settings(),
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
                    'Hello, Ivan',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.8,
                      color: const Color(0xff17233b),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome to AiRobot',
                    style: TextStyle(
                      fontSize: 16,
                      color: const Color(0xff718096),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xffd3e3fd),
              child: Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: Color(0xff1a73e8),
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
              onPressed: () => selectPage(3),
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
                accentColor: const [
                  Color(0xff38bdf8),
                  Color(0xff34d399),
                  Color(0xffa78bfa),
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
      const Text(
        'Desarmar detiene el movimiento y mantiene la consigna. No corta la alimentación de los servos.',
      ),
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
              color: const Color(0xfff8fafc),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffe2e8f0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: joint,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xff64748b),
                  size: 22,
                ),
                borderRadius: BorderRadius.circular(16),
                dropdownColor: Colors.white,
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
                                  ? const Color(0xffd3e3fd)
                                  : const Color(0xffe2e8f0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'J${j + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: joint == j
                                    ? const Color(0xff0842a0)
                                    : const Color(0xff475569),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              names[j],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xff1e293b),
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
          if (joint == 1)
            const Text(
              'J2 coordina dos servos calibrados.',
              style: TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget manualRecovery() => Wrap(
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffe6e6e6)),
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
                      ? const Color(0xff17233b)
                      : const Color(0xff9ca3af),
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
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(Icons.control_camera, color: Color(0xff9ca3af)),
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
          color: const Color(0xfff8fafc),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffe2e8f0)),
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff1e293b),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorStyle: const TextStyle(height: 0.8, fontSize: 10),
                  suffixText: unit,
                  suffixStyle: const TextStyle(
                    fontSize: 11,
                    color: Color(0xff94a3b8),
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
                            color: const Color(0xffd3e3fd),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'XYZ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xff0842a0),
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
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xfff1f5f9),
                      foregroundColor: const Color(0xff1e293b),
                    ),
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
                      accentColor: const Color(0xff38bdf8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _minimalInput(
                      label: 'Y',
                      unit: 'mm',
                      controller: py,
                      isGripper: false,
                      accentColor: const Color(0xff34d399),
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
                      accentColor: const Color(0xffa78bfa),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _minimalInput(
                      label: 'J7',
                      unit: '°',
                      controller: grip,
                      isGripper: true,
                      accentColor: const Color(0xfff59e0b),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xffe2e8f0)),
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
                      title: const Text(
                        'Conservar orientación',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff1e293b),
                        ),
                      ),
                      subtitle: Text(
                        keepOrientation
                            ? 'Mantiene la orientación actual de la garra'
                            : 'Usa la orientación de home',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff64748b),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff0f172a),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
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
      color: const Color(0xfff8fafc),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffe2e8f0)),
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
            Icon(icon, size: 16, color: const Color(0xff0284c7)),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xff334155),
                letterSpacing: -.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xff0369a1),
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
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Eliminar paso',
                      onPressed: () => setState(() => vm.steps.removeAt(i)),
                      icon: const Icon(Icons.close),
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
      OutlinedButton.icon(
        onPressed: vm.repository != null
            ? () => run(vm.loadPrograms, success: 'Programas actualizados')
            : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar'),
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
                Text(
                  '${(p['body']['steps'] as List).length} puntos · ${p['needsRevalidation'] == true ? 'Requiere revalidación' : 'Perfil compatible'}',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: vm.canMove && p['needsRevalidation'] != true
                          ? () => run(() => vm.run(p))
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
                      onPressed: () => run(() async {
                        await vm.repository!.deleteProgram(p['id']);
                        await vm.loadPrograms();
                      }),
                      icon: const Icon(Icons.delete_outline),
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
                : (enabled) => run(
                    () => vm.setSimulationMode(enabled),
                    success: enabled
                        ? 'Simulador conectado'
                        : 'Simulador desconectado',
                  ),
          ),
        ),
      ),
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
            const Text(
              'Bloquear movimiento es una parada por software. No corta la alimentación de los servos.',
              style: TextStyle(color: Color(0xff5d5d5d)),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> reference() async {
    final controllers = List.generate(
      7,
      (i) => TextEditingController(
        text: vm.snapshot.simulation ? vm.profile?.home[i].toString() : '',
      ),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                    for (int i = 0; i < 7; i++)
                      field('J${i + 1} · °', controllers[i]),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              run(() => vm.reference(controllers.map(value).toList()));
              Navigator.pop(ctx);
            },
            child: const Text('Confirmar ángulos'),
          ),
        ],
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
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

  Future<void> confirmRevalidation(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revalidar con el perfil actual'),
        content: const Text(
          'Los mismos puntos pueden producir movimientos distintos tras cambiar home o geometría. Se validarán de nuevo y se guardará una revisión; no se ejecutará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar revalidación'),
          ),
        ],
      ),
    );
    if (ok == true) run(() => vm.revalidate(p));
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
