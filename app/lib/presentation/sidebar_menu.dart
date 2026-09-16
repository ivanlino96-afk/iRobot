import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Navigation only: account and robot operations remain outside the sidebar.
class SidebarMenu extends StatefulWidget {
  const SidebarMenu({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.onClose,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onClose;

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  bool expanded = true;
  static const labels = [
    'Home',
    'Manual',
    'Programas',
    'Enseñar',
    'Configurar',
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.open_with,
    Icons.playlist_play,
    Icons.add_location_alt_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final open = widget.onClose != null || expanded;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOutCubic,
      width: open ? 252 : 80,
      margin: widget.onClose == null
          ? const EdgeInsets.fromLTRB(12, 12, 0, 12)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xffe7ebf3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080f2340),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = open && constraints.maxWidth > 220;
          return Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: 76,
                    child: Row(
                      children: [
                        if (showLabels) ...[
                          const SizedBox(width: 20),
                          Icon(
                            Icons.precision_manufacturing_outlined,
                            color: colors.primary,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'AiRobot',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        IconButton(
                          tooltip: widget.onClose != null
                              ? 'Cerrar menú'
                              : open
                              ? 'Contraer menú'
                              : 'Expandir menú',
                          onPressed:
                              widget.onClose ??
                              () {
                                HapticFeedback.selectionClick();
                                setState(() => expanded = !expanded);
                              },
                          icon: Icon(
                            widget.onClose != null
                                ? Icons.close
                                : open
                                ? Icons.keyboard_double_arrow_left
                                : Icons.keyboard_double_arrow_right,
                            size: 20,
                          ),
                        ),
                        if (!showLabels)
                          const Spacer()
                        else
                          const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 20,
                      ),
                      children: [
                        if (showLabels)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 0, 0, 12),
                            child: Text(
                              'ESPACIO DE TRABAJO',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.1,
                                color: Color(0xff8b95a5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        for (int i = 0; i < labels.length; i++) ...[
                          if (i == 4) const Divider(height: 32),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Tooltip(
                              message: showLabels ? '' : labels[i],
                              child: Semantics(
                                selected: widget.selectedIndex == i,
                                child: InkWell(
                                  key: ValueKey('sidebar-$i'),
                                  borderRadius: BorderRadius.circular(13),
                                  onTap: () => widget.onSelected(i),
                                  child: AnimatedContainer(
                                    duration: duration,
                                    height: 50,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: widget.selectedIndex == i
                                          ? colors.primaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          icons[i],
                                          size: 22,
                                          color: widget.selectedIndex == i
                                              ? colors.primary
                                              : const Color(0xff718096),
                                        ),
                                        if (showLabels) ...[
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              labels[i],
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    widget.selectedIndex == i
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                                color: widget.selectedIndex == i
                                                    ? colors.onPrimaryContainer
                                                    : const Color(0xff596477),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Invitado · Perfil provisional',
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xffe7ebf3)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: colors.primaryContainer,
                            child: Icon(
                              Icons.person_outline,
                              size: 21,
                              color: colors.primary,
                            ),
                          ),
                          if (showLabels) ...[
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Invitado',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Perfil provisional',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xff8b95a5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
