import 'package:flutter/material.dart';

class JogButton extends StatefulWidget {
  const JogButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onStep,
    required this.onHold,
    required this.onRelease,
  });
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onStep, onHold, onRelease;
  @override
  State<JogButton> createState() => _JogButtonState();
}

class _JogButtonState extends State<JogButton> {
  bool held = false;
  void release() {
    if (!held) return;
    held = false;
    widget.onRelease();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: '${widget.label}. Pulsar para un paso; mantener para repetir.',
    child: GestureDetector(
      onLongPressStart: widget.enabled
          ? (_) {
              setState(() => held = true);
              widget.onHold();
            }
          : null,
      onLongPressEnd: (_) => release(),
      onLongPressCancel: release,
      onLongPressMoveUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null &&
            !(Offset.zero & box.size).contains(details.localPosition)) {
          release();
        }
      },
      child: Listener(
        onPointerCancel: (_) => release(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: held
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: OutlinedButton.icon(
            onPressed: widget.enabled ? widget.onStep : null,
            icon: Icon(widget.icon, size: 20),
            label: Text(widget.label),
          ),
        ),
      ),
    ),
  );
}
