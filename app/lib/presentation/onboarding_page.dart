import 'package:flutter/material.dart';
import 'login_page.dart';
import 'robot_view_model.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, required this.vm});
  final RobotViewModel vm;

  void _continue(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LoginPage(vm: vm)));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: screenHeight * 0.32,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Image.asset(
                      'assets/onboarding_robot.png',
                      width: screenWidth * 0.72,
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: () => _continue(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                      ),
                      child: const Text(
                        'Omitir',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const _Badge(),
                  const SizedBox(height: 22),
                  const Text(
                    'CONTROLA\nTU BRAZO\nROBÓTICO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 40,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mueve, enseña y ejecuta secuencias en tu brazo '
                    'robótico de 6 grados de libertad desde cualquier lugar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.62),
                    ),
                  ),
                  const Spacer(flex: 3),
                  const _Dots(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => _continue(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 6,
                        shadowColor: Colors.black.withValues(alpha: 0.25),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: const Text(
                        'Continuar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffc6e1f7), Color(0xffc8c6f6), Color(0xffe3e0f4)],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 22,
            child: Stack(
              children: [
                _badgeIcon(Icons.bolt_rounded, 0),
                _badgeIcon(Icons.settings_input_component_rounded, 13),
                _badgeIcon(Icons.precision_manufacturing_rounded, 26),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'CONTROL EN TIEMPO REAL',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeIcon(IconData icon, double left) => Positioned(
    left: left,
    child: Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: Icon(icon, size: 12, color: Colors.black),
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [_dot(active: true), _gap(), _dot(), _gap(), _dot()],
  );

  Widget _gap() => const SizedBox(width: 6);

  Widget _dot({bool active = false}) => Container(
    width: active ? 22 : 7,
    height: 7,
    decoration: BoxDecoration(
      color: active ? Colors.black : Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
