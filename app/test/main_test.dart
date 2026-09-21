import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/main.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/login_page.dart';
import 'package:airobot/presentation/onboarding_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  testWidgets(
    'Sin sesión real, la app muestra la bienvenida y nunca la pantalla principal',
    (tester) async {
      await tester.pumpWidget(const AiRobotApp());
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    },
  );

  testWidgets('Continuar en la bienvenida lleva al login', (tester) async {
    await tester.pumpWidget(const AiRobotApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });
}
