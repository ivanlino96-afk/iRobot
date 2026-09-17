import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'safety_notice.dart';

class MotionPopup extends StatelessWidget {
  const MotionPopup({
    super.key,
    required this.status,
    required this.unconfirmed,
    required this.stopping,
    required this.onStop,
    required this.onDismiss,
  });
  final String status;
  final bool unconfirmed, stopping;
  final VoidCallback onStop, onDismiss;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const ModalBarrier(dismissible: false, color: Color(0x66000000)),
      Center(
        child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
          namesRoute: true,
          label: 'Estado de movimiento',
          child: AlertDialog(
            icon: Icon(
              unconfirmed
                  ? Icons.warning_amber_rounded
                  : Icons.precision_manufacturing_outlined,
              size: 36,
              color: unconfirmed
                  ? context.tokens.danger
                  : Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              unconfirmed
                  ? 'Estado sin confirmar'
                  : stopping
                  ? 'Deteniendo…'
                  : 'En movimiento',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!unconfirmed) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(status, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.tokens.danger,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 56),
                    ),
                    onPressed: stopping ? null : onStop,
                    icon: const Icon(Icons.stop_rounded, size: 26),
                    label: Text(
                      stopping ? 'Solicitando parada…' : 'Stop',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const SafetyNotice(textAlign: TextAlign.center),
                if (unconfirmed)
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Cerrar aviso'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
