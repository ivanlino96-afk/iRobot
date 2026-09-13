import 'package:flutter/material.dart';

ThemeData airobotTheme() {
  const ink = Color(0xff0d0d0d), muted = Color(0xff5d5d5d);
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light, fontFamily: const String.fromEnvironment('AIROBOT_FONT_FAMILY', defaultValue: '.SF Pro Text'));
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: ink,
      primary: ink,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xfffafafa),
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w400,
            letterSpacing: -1.4,
            color: ink,
          ),
          headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w400,
            letterSpacing: -.8,
            color: ink,
          ),
          bodyLarge: const TextStyle(fontSize: 17, height: 1.45, color: ink),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.45, color: ink),
          bodySmall: const TextStyle(fontSize: 13, color: muted),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xfffafafa),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        minimumSize: const Size(44, 48),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(44, 48),
        side: const BorderSide(color: Color(0xffdedede)),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xffdedede)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xffdedede)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xffe6e6e6),
      thickness: 1,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xffececf2),
    ),
  );
}
