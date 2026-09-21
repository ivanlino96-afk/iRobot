import 'package:flutter/material.dart';
import 'presentation/theme.dart';
import 'presentation/home_page.dart';
import 'presentation/onboarding_page.dart';
import 'presentation/robot_view_model.dart';

void main() => runApp(const AiRobotApp());

class AiRobotApp extends StatefulWidget {
  const AiRobotApp({super.key});
  @override
  State<AiRobotApp> createState() => _AiRobotAppState();
}

class _AiRobotAppState extends State<AiRobotApp> {
  late final RobotViewModel vm = RobotViewModel();

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: vm,
    builder: (context, _) => MaterialApp(
      title: 'AiRobot',
      debugShowCheckedModeBanner: false,
      theme: airobotTheme(),
      darkTheme: airobotTheme(brightness: Brightness.dark),
      themeMode: vm.themeMode,
      home: _SessionGate(vm: vm),
    ),
  );
}

// Gatekeeper: no se monta HomePage sin una sesión real restaurada. Reacciona
// a vm.api (login/logout) para alternar entre LoginPage y HomePage sin
// depender del stack de Navigator.
class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.vm});
  final RobotViewModel vm;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  bool checking = true;

  @override
  void initState() {
    super.initState();
    widget.vm.tryAutoConnect().catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => checking = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (checking) return const _SessionSplash();
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (context, _) => widget.vm.api == null
          ? OnboardingPage(vm: widget.vm)
          : HomePage(model: widget.vm),
    );
  }
}

class _SessionSplash extends StatelessWidget {
  const _SessionSplash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.precision_manufacturing_outlined, size: 56),
          SizedBox(height: 16),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}
