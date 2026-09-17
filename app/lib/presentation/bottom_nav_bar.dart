import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Thin, floating bottom navigation bar for narrow (phone) layouts.
/// White background, light-gray highlight on the selected destination.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const labels = [
    'Home',
    'Manual',
    'Programas',
    'Enseñar',
    'Configurar',
    'Diagnóstico',
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.open_with,
    Icons.playlist_play,
    Icons.add_location_alt_outlined,
    Icons.settings_outlined,
    Icons.monitor_heart_outlined,
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 12,
    shadowColor: const Color(0x33101828),
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < labels.length; i++)
            Tooltip(
              message: labels[i],
              child: Semantics(
                selected: selectedIndex == i,
                button: true,
                label: labels[i],
                child: InkWell(
                  key: ValueKey('bottom-nav-$i'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    if (selectedIndex != i) HapticFeedback.selectionClick();
                    onSelected(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selectedIndex == i
                          ? const Color(0xffeef0f3)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icons[i],
                      size: 22,
                      color: selectedIndex == i
                          ? const Color(0xff17233b)
                          : const Color(0xff9aa5b8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
