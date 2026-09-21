import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design_tokens.dart';
import 'login_page.dart';
import 'robot_view_model.dart';

/// Navigation only: account and robot operations remain outside the sidebar.
class SidebarMenu extends StatefulWidget {
  const SidebarMenu({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.vm,
    this.onClose,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final RobotViewModel vm;
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = context.tokens;
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
        color: colors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: tokens.cardBorder),
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                            child: Text(
                              'ESPACIO DE TRABAJO',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.1,
                                color: tokens.muted,
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
                                              : tokens.muted,
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
                                                    : tokens.ink,
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
                  Builder(
                    builder: (context) {
                      final loggedIn = widget.vm.api != null;
                      final name = widget.vm.userName;
                      final displayName = loggedIn
                          ? ((name?.isNotEmpty ?? false)
                                ? name!
                                : 'Sesión iniciada')
                          : 'Invitado';
                      final subtitle = loggedIn
                          ? 'Cuenta AiRobot'
                          : 'Perfil provisional';
                      void openLogin() {
                        widget.onClose?.call();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LoginPage(vm: widget.vm),
                          ),
                        );
                      }

                      Future<void> editName() async {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => _EditNameDialog(vm: widget.vm),
                        );
                      }

                      return Tooltip(
                        message: loggedIn
                            ? '$displayName · $subtitle'
                            : '$displayName · $subtitle · Toca para iniciar sesión',
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: tokens.cardBorder),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: loggedIn ? editName : openLogin,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  mainAxisAlignment: showLabels
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
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
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: tokens.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: const ValueKey('sidebar-logout'),
                                        tooltip: loggedIn
                                            ? 'Cerrar sesión'
                                            : 'Iniciar sesión',
                                        iconSize: 20,
                                        onPressed: loggedIn
                                            ? () async {
                                                await widget.vm.logout();
                                                if (!context.mounted) return;
                                                widget.onClose?.call();
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => LoginPage(
                                                      vm: widget.vm,
                                                    ),
                                                  ),
                                                );
                                              }
                                            : openLogin,
                                        icon: Icon(
                                          loggedIn
                                              ? Icons.logout
                                              : Icons.login,
                                          color: tokens.muted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.vm});
  final RobotViewModel vm;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final controller = TextEditingController(text: widget.vm.userName);
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
      await widget.vm.updateDisplayName(controller.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = 'No se pudo guardar el nombre.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tu nombre'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          maxLength: 254,
          decoration: const InputDecoration(labelText: 'Nombre completo'),
          onChanged: (_) => setState(() {}),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
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
            : const Text('Guardar'),
      ),
    ],
  );
}
