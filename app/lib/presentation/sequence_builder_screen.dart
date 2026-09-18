import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'robot_view_model.dart';
import 'jog_button.dart';
import 'motion_popup.dart';
import 'design_tokens.dart';
import 'safety_notice.dart';

/// Guided point-capture flow for a new sequence. Unlike the legacy "Enseñar"
/// screen, points are named as they're saved and "Guardar punto" is gated by
/// a settle delay after the last confirmed motion: the MG995 servos report no
/// real position feedback, so `vm.snapshot.tcp` is always a commanded target,
/// never a measurement, and saving mid-trajectory would capture a stale value.
class SequenceBuilderScreen extends StatefulWidget {
  const SequenceBuilderScreen({
    super.key,
    required this.vm,
    required this.sequenceName,
  });
  final RobotViewModel vm;
  final String sequenceName;

  @override
  State<SequenceBuilderScreen> createState() => _SequenceBuilderScreenState();
}

class _SequenceBuilderScreenState extends State<SequenceBuilderScreen> {
  RobotViewModel get vm => widget.vm;
  int speed = 10;
  double linearStep = 5, angularStep = 5;
  final pause = TextEditingController(text: '500');
  bool _settled = false;
  bool _wasIdle = false;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _wasIdle = vm.isIdle;
    _settled = vm.isIdle;
    vm.addListener(_onVmChanged);
  }

  @override
  void dispose() {
    vm.removeListener(_onVmChanged);
    _settleTimer?.cancel();
    pause.dispose();
    super.dispose();
  }

  // Runs once per EXECUTING→READY edge (not on every telemetry tick) so the
  // settle timer isn't restarted while the robot is already sitting still.
  void _onVmChanged() {
    final idle = vm.isIdle;
    if (idle && !_wasIdle) {
      _settleTimer?.cancel();
      _settled = false;
      _settleTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _settled = true);
      });
    } else if (!idle && _wasIdle) {
      _settleTimer?.cancel();
      _settled = false;
    }
    _wasIdle = idle;
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

  double? _axisValue(int axis) =>
      vm.snapshot.connected && vm.snapshot.reference && vm.snapshot.tcp != null
      ? vm.snapshot.tcp![axis]
      : null;

  Widget _axisIndicator(String label, double? value, Color accent) =>
      Container(
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  'EJE $label',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                child: Text(
                  value != null ? value.toStringAsFixed(1) : '—',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: context.tokens.muted,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'mm',
                style: TextStyle(fontSize: 11, color: context.tokens.muted),
              ),
            ],
          ),
        ),
      );

  Widget _axisRow() => Row(
    children: [
      Expanded(
        child: _axisIndicator('X', _axisValue(0), context.tokens.axisX),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _axisIndicator('Y', _axisValue(1), context.tokens.axisY),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _axisIndicator('Z', _axisValue(2), context.tokens.axisZ),
      ),
    ],
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

  Widget _jogControls() => card(
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

  Future<String?> _promptPointName() => showDialog<String>(
    context: context,
    builder: (ctx) => _PointNameDialog(initial: 'Punto ${vm.steps.length + 1}'),
  );

  Future<void> _savePoint() async {
    final name = await _promptPointName();
    if (name == null) return;
    await run(
      () async => vm.teach(speed, pauseValue(), name: name),
      success: 'Punto guardado',
    );
  }

  Widget _captureCard() {
    final ready =
        _settled &&
        vm.snapshot.reference &&
        vm.snapshot.tcp != null &&
        !vm.busy &&
        !vm.holding;
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comandada, no medida',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            ready
                ? 'Listo para guardar el punto'
                : 'Esperando a que el movimiento se estabilice…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ready ? context.tokens.success : context.tokens.warning,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              field('Pausa · ms', pause),
              FilledButton.icon(
                onPressed: ready ? _savePoint : null,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Guardar punto'),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            onChanged: vm.holding
                ? null
                : (v) => setState(() => speed = v.round()),
          ),
        ],
      ),
    );
  }

  Future<void> _editPoint(int i) async {
    final step = vm.steps[i];
    await showDialog(
      context: context,
      builder: (_) => _EditPointDialog(
        step: step,
        index: i,
        onSave: (build) => run(() async {
          vm.steps[i] = build();
        }),
      ),
    );
  }

  Widget _pointsList() {
    if (vm.steps.isEmpty) {
      return card(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Sin puntos. Mueve el robot con las flechas y guarda su posición.',
            style: TextStyle(color: context.tokens.muted),
          ),
        ),
      );
    }
    return card(
      Column(
        children: [
          for (int i = 0; i < vm.steps.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text('${i + 1}'.padLeft(2, '0')),
              title: Text(
                vm.steps[i].name.isEmpty ? 'Punto ${i + 1}' : vm.steps[i].name,
              ),
              subtitle: Text(
                '${vm.steps[i].tcp.map((x) => x.toStringAsFixed(1)).join(' / ')} mm · '
                '${vm.steps[i].speed}% · ${vm.steps[i].pauseMs} ms · garra ${vm.steps[i].gripper}°',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Editar punto',
                    onPressed: () => _editPoint(i),
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
                    tooltip: 'Eliminar punto',
                    onPressed: () async {
                      if (await confirm(
                        '¿Eliminar este punto?',
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
        ],
      ),
    );
  }

  Future<void> _finish() async {
    await run(
      () => vm.save(widget.sequenceName),
      success: 'Secuencia guardada',
    );
    if (!vm.actionFailed && mounted) {
      vm.discardSteps();
      Navigator.of(context).pop();
    }
  }

  Future<void> _handlePop() async {
    if (vm.motionPopupVisible) return;
    if (vm.steps.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (await confirm(
      '¿Descartar secuencia?',
      'Tienes ${vm.steps.length} punto(s) sin guardar. Si sales ahora se perderán.',
      confirmLabel: 'Descartar',
      destructive: true,
    )) {
      vm.discardSteps();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: vm,
    builder: (context, _) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handlePop();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(title: Text(widget.sequenceName)),
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (vm.busy) const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 12),
                      _axisRow(),
                      const SizedBox(height: 20),
                      _jogControls(),
                      const SizedBox(height: 20),
                      _captureCard(),
                      const SizedBox(height: 20),
                      Text(
                        'Puntos guardados · ${vm.steps.length}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _pointsList(),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: vm.steps.isNotEmpty && !vm.busy
                            ? _finish
                            : null,
                        child: const Text('Guardar secuencia'),
                      ),
                      const SizedBox(height: 8),
                      const SafetyNotice(textAlign: TextAlign.center),
                    ],
                  ),
                ),
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
    ),
  );
}

// Owns its TextEditingController via normal widget lifecycle instead of
// disposing it right after showDialog's future resolves, which races the
// dialog's closing transition and crashes when the autofocused field loses
// focus mid-animation.
class _PointNameDialog extends StatefulWidget {
  const _PointNameDialog({required this.initial});
  final String initial;

  @override
  State<_PointNameDialog> createState() => _PointNameDialogState();
}

class _PointNameDialogState extends State<_PointNameDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nombre del punto'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Nombre'),
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Guardar punto'),
      ),
    ],
  );
}

// Same rationale as _PointNameDialog: owns its TextEditingControllers via
// normal widget lifecycle instead of disposing them right after showDialog's
// future resolves.
class _EditPointDialog extends StatefulWidget {
  const _EditPointDialog({
    required this.step,
    required this.index,
    required this.onSave,
  });

  final ProgramStep step;
  final int index;
  final void Function(ProgramStep Function() build) onSave;

  @override
  State<_EditPointDialog> createState() => _EditPointDialogState();
}

class _EditPointDialogState extends State<_EditPointDialog> {
  late final nameController = TextEditingController(text: widget.step.name);
  late final controllers = [
    for (final v in [
      ...widget.step.tcp,
      widget.step.gripper,
      widget.step.speed,
      widget.step.pauseMs,
    ])
      TextEditingController(text: '$v'),
  ];

  @override
  void dispose() {
    nameController.dispose();
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  ProgramStep _build() {
    double val(int idx) {
      final v = double.tryParse(controllers[idx].text.replaceAll(',', '.'));
      if (v == null || !v.isFinite) {
        throw const FormatException('Introduce un número válido');
      }
      return v;
    }

    final vals = List.generate(6, val);
    if (vals[4] != vals[4].roundToDouble() ||
        vals[5] != vals[5].roundToDouble()) {
      throw const FormatException('Velocidad y pausa deben ser enteros');
    }
    return ProgramStep(
      tcp: vals.take(3).toList(),
      gripper: vals[3],
      speed: vals[4].toInt(),
      pauseMs: vals[5].toInt(),
      name: nameController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return AlertDialog(
      title: Text(
        'Editar ${step.name.isEmpty ? 'punto ${widget.index + 1}' : step.name}',
      ),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 292,
              child: TextField(
                controller: nameController,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
            ),
            for (int j = 0; j < 6; j++)
              SizedBox(
                width: 140,
                child: TextField(
                  controller: controllers[j],
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        [
                          'X mm',
                          'Y mm',
                          'Z mm',
                          'Garra °',
                          'Velocidad %',
                          'Pausa ms',
                        ][j],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_build);
            Navigator.pop(context);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
