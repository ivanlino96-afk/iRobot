import 'package:flutter/material.dart';
import 'presentation/theme.dart';
import 'presentation/home_page.dart';
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
      home: HomePage(model: vm),
    ),
  );
}
