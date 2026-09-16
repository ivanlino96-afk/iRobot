import 'package:flutter/material.dart';

ThemeData airobotTheme() {
  const ink = Color(0xff17233b), muted = Color(0xff718096);
  const primary = Color(0xff1a73e8);
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xffd3e3fd),
    onPrimaryContainer: const Color(0xff0842a0),
    secondary: const Color(0xff1967d2),
    secondaryContainer: const Color(0xffd3e3fd),
    onSecondaryContainer: const Color(0xff0842a0),
    tertiary: const Color(0xff4285f4),
    surface: Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: const String.fromEnvironment(
      'AIROBOT_FONT_FAMILY',
      defaultValue: '.SF Pro Text',
    ),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xfff0f4f9),
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: ink,
          ),
          headlineMedium: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
            color: ink,
          ),
          headlineSmall: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
            color: ink,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.4, color: ink),
          bodySmall: const TextStyle(fontSize: 12, height: 1.4, color: muted),
        )
        .apply(
          fontFamily: const String.fromEnvironment(
            'AIROBOT_FONT_FAMILY',
            defaultValue: '.SF Pro Text',
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xfff0f4f9),
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
        side: const BorderSide(color: Color(0xffdce2ed)),
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
      backgroundColor: Colors.white,
      selectedColor: const Color(0xffd3e3fd),
      side: const BorderSide(color: Color(0xffe2e7f0)),
      shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xfff6f8fc),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xffe7ebf3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      insetPadding: const EdgeInsets.all(16),
      showCloseIcon: true,
      closeIconColor: Colors.white,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xffe7ebf3),
      thickness: 1,
      space: 24,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0xffd3e3fd),
      height: 72,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xffd3e3fd),
    ),
  );
}
