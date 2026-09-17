import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'login_page.dart';

/// Onboarding splash screen, shape inspired by a common two-panel
/// (illustration + rounded white card) pattern. Visual-only for now.
class GetStartedPage extends StatelessWidget {
  const GetStartedPage({super.key});

  static const _background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xffc6e1f7), Color(0xffc8c6f6), Color(0xffe3e0f4)],
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: _background),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: Center(
                  child: Icon(
                    Icons.precision_manufacturing_outlined,
                    size: 132,
                    color: const Color(0xff0d0d0d).withValues(alpha: 0.82),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'AIROBOT',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Controla tu robot\ncon total confianza',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Conecta, mueve y enseña secuencias a tu brazo robótico desde una sola app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: tokens.muted, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            ),
                            child: const Text(
                              'Comenzar',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
