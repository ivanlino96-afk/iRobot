import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.onGoHome,
    required this.onCreateSequence,
  });
  final VoidCallback? onGoHome;
  final VoidCallback onCreateSequence;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    consumeOutsideTap: true,
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surface,
      ),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(8),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
    ),
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.home_outlined),
        onPressed: onGoHome,
        child: const Text('Ir a home'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.add_location_alt_outlined),
        onPressed: onCreateSequence,
        child: const Text('Crear secuencia'),
      ),
    ],
    builder: (context, controller, child) => FloatingActionButton(
      heroTag: 'quick-actions',
      tooltip: 'Acciones rápidas',
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
      elevation: 5,
      onPressed: () {
        HapticFeedback.selectionClick();
        controller.isOpen ? controller.close() : controller.open();
      },
      child: const Icon(Icons.bolt_rounded, size: 30),
    ),
  );
}
