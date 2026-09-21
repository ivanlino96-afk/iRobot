import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'robot_view_model.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.vm});
  final RobotViewModel vm;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final confirmPassword = TextEditingController();
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool isRegisterMode = false;
  bool submitting = false;
  String? error;

  Future<void> submit() async {
    if (isRegisterMode && name.text.trim().isEmpty) {
      setState(() => error = 'Introduce tu nombre completo.');
      return;
    }
    if (isRegisterMode && password.text != confirmPassword.text) {
      setState(() => error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.vm.login(
        'https://api.3dlab.site',
        email.text.trim(),
        password.text,
        isRegisterMode,
        name: isRegisterMode ? name.text.trim() : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = _describeError(e));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  String _describeError(Object e) {
    if (e is DioException) {
      final code = (e.response?.data is Map) ? e.response!.data['error'] : null;
      switch (code) {
        case 'invalid-login':
          return isRegisterMode
              ? 'No se pudo crear la cuenta.'
              : 'Usuario no registrado o contraseña incorrecta.';
        case 'email':
          return 'Introduce un correo electrónico válido.';
        case 'password-minimum-12':
          return 'La contraseña debe tener al menos 12 caracteres.';
        case 'try-later':
          return 'Demasiados intentos. Espera un momento y vuelve a intentarlo.';
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'No se pudo conectar con el servidor. Revisa tu conexión.';
      }
    }
    return 'No se pudo continuar. Inténtalo de nuevo.';
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  static const _background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xffc6e1f7), Color(0xffc8c6f6), Color(0xffe3e0f4)],
  );

  void _comingSoon(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Inicio con $provider disponible próximamente.')),
    );
  }

  Widget _labeledField({
    required String label,
    required Widget field,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      field,
    ],
  );

  Widget _socialButton({
    required Widget icon,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    height: 50,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xfff2f3f5),
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.arrow_back,
                        color: const Color(0xff0d0d0d).withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 26),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.82,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              isRegisterMode
                                  ? 'Crea tu cuenta'
                                  : 'Bienvenido de nuevo',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              isRegisterMode
                                  ? 'Crea una cuenta para sincronizar el perfil de tu brazo robótico y tus secuencias en la nube.'
                                  : 'Inicia sesión para controlar tu brazo robótico, revisar su estado y retomar tus secuencias guardadas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: tokens.muted, height: 1.4),
                            ),
                          ),
                          const SizedBox(height: 26),
                          if (isRegisterMode) ...[
                            _labeledField(
                              label: 'Nombre completo',
                              field: TextField(
                                controller: name,
                                keyboardType: TextInputType.name,
                                decoration: const InputDecoration(
                                  hintText: 'Tu nombre y apellido',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _labeledField(
                            label: 'Correo electrónico',
                            field: TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'tu@correo.com',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _labeledField(
                            label: 'Contraseña',
                            field: TextField(
                              controller: password,
                              obscureText: obscurePassword,
                              decoration: InputDecoration(
                                hintText: '••••••••••••',
                                suffixIcon: IconButton(
                                  tooltip: obscurePassword
                                      ? 'Mostrar contraseña'
                                      : 'Ocultar contraseña',
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (isRegisterMode) ...[
                            const SizedBox(height: 16),
                            _labeledField(
                              label: 'Confirmar contraseña',
                              field: TextField(
                                controller: confirmPassword,
                                obscureText: obscureConfirmPassword,
                                decoration: InputDecoration(
                                  hintText: '••••••••••••',
                                  suffixIcon: IconButton(
                                    tooltip: obscureConfirmPassword
                                        ? 'Mostrar contraseña'
                                        : 'Ocultar contraseña',
                                    icon: Icon(
                                      obscureConfirmPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () => obscureConfirmPassword =
                                          !obscureConfirmPassword,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (!isRegisterMode) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '¿Olvidaste tu contraseña?',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                          if (error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: submitting ? null : submit,
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                              child: submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      isRegisterMode
                                          ? 'Crear cuenta'
                                          : 'Iniciar sesión',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _socialButton(
                            icon: const Text(
                              'G',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xff1a73e8),
                              ),
                            ),
                            label: 'Continuar con Google',
                            onPressed: () => _comingSoon('Google'),
                          ),
                          const SizedBox(height: 12),
                          _socialButton(
                            icon: const Icon(Icons.apple, size: 22),
                            label: 'Continuar con Apple',
                            onPressed: () => _comingSoon('Apple'),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: submitting
                                  ? null
                                  : () => setState(
                                      () => isRegisterMode = !isRegisterMode,
                                    ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: tokens.muted,
                                      fontSize: 13,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: isRegisterMode
                                            ? '¿Ya tienes cuenta? '
                                            : '¿No tienes cuenta? ',
                                      ),
                                      TextSpan(
                                        text: isRegisterMode
                                            ? 'Inicia sesión'
                                            : 'Regístrate',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(top: 0, child: _BrandMark()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.precision_manufacturing_outlined,
          size: 22,
          color: Color(0xff1a73e8),
        ),
        SizedBox(width: 8),
        Text(
          'AiRobot',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xff0d0d0d),
          ),
        ),
      ],
    ),
  );
}
