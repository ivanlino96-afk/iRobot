import 'package:flutter/material.dart';
import 'design_tokens.dart';

ThemeData airobotTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? AirobotTokens.dark : AirobotTokens.light;
  final ink = tokens.ink, muted = tokens.muted;
  const primary = Color(0xff1a73e8);
  final surface = dark ? const Color(0xff14181f) : Colors.white;
  final scaffoldBg = dark ? const Color(0xff10141c) : const Color(0xfff0f4f9);
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xff173156) : const Color(0xffd3e3fd),
    onPrimaryContainer: dark ? const Color(0xffd3e3fd) : const Color(0xff0842a0),
    secondary: const Color(0xff1967d2),
    secondaryContainer: dark
        ? const Color(0xff173156)
        : const Color(0xffd3e3fd),
    onSecondaryContainer: dark
        ? const Color(0xffd3e3fd)
        : const Color(0xff0842a0),
    tertiary: const Color(0xff4285f4),
    surface: surface,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: const String.fromEnvironment(
      'AIROBOT_FONT_FAMILY',
      defaultValue: '.SF Pro Text',
    ),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    scaffoldBackgroundColor: scaffoldBg,
    splashFactory: InkSparkle.splashFactory,
    extensions: [tokens],
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
            color: ink,
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: ink),
          bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
        )
        .apply(
          fontFamily: const String.fromEnvironment(
            'AIROBOT_FONT_FAMILY',
            defaultValue: '.SF Pro Text',
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBg,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: shape,
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: tokens.cardBorder),
        shape: shape,
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surface,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: tokens.cardBorder),
      shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xff2a3242) : ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      insetPadding: const EdgeInsets.all(16),
      showCloseIcon: true,
      closeIconColor: Colors.white,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: tokens.cardBorder,
      thickness: 1,
      space: 24,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      height: 72,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}
