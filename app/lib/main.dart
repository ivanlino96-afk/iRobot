import 'package:flutter/material.dart';
import 'presentation/theme.dart';
import 'presentation/home_page.dart';

void main() => runApp(const AiRobotApp());

class AiRobotApp extends StatelessWidget {
  const AiRobotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AiRobot',
    debugShowCheckedModeBanner: false,
    theme: airobotTheme(),
    home: const HomePage(),
  );
}
