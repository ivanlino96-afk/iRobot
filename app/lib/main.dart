import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() => runApp(const ProviderScope(child: AiRobotApp()));

class RobotState {
  const RobotState({this.connected = false, this.status = 'Sin conexión', this.x = 0, this.y = 0, this.z = 0});
  final bool connected;
  final String status;
  final double x;
  final double y;
  final double z;
  RobotState copyWith({bool? connected, String? status, double? x, double? y, double? z}) => RobotState(
      connected: connected ?? this.connected, status: status ?? this.status, x: x ?? this.x, y: y ?? this.y, z: z ?? this.z);
}
class RobotController extends Notifier<RobotState> {
  @override RobotState build() => const RobotState(connected: true, status: 'Conectado');
  void setTarget(double x, double y, double z) => state = state.copyWith(x: x, y: y, z: z, status: 'Objetivo enviado');
  void goHome() => state = state.copyWith(x: 0, y: 0, z: 0, status: 'Home solicitado');
  void emergencyStop() => state = state.copyWith(status: 'Parada de emergencia');
}
final robotProvider = NotifierProvider<RobotController, RobotState>(RobotController.new);

class AiRobotApp extends StatelessWidget {
  const AiRobotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AiRobot',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2768f4), brightness: Brightness.light),
      scaffoldBackgroundColor: const Color(0xfff7f9ff),
      textTheme: Theme.of(context).textTheme.apply(bodyColor: const Color(0xff17213a), displayColor: const Color(0xff17213a)),
    ),
    home: const RobotHomePage(),
  );
}

class RobotHomePage extends ConsumerStatefulWidget {
  const RobotHomePage({super.key});
  @override ConsumerState<RobotHomePage> createState() => _RobotHomePageState();
}

class _RobotHomePageState extends ConsumerState<RobotHomePage> {
  int index = 0;
  final x = TextEditingController(text: '120');
  final y = TextEditingController(text: '80');
  final z = TextEditingController(text: '140');
  final labels = const ['Control', 'Mover TCP', 'Programas', 'Enseñar', 'Configurar'];
  @override void dispose() { x.dispose(); y.dispose(); z.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final robot = ref.watch(robotProvider);
    final page = index == 1 ? _tcpPanel() : _placeholder(labels[index]);
    return Scaffold(
      appBar: AppBar(title: const Text('AiRobot'), actions: [
        Chip(label: Text(robot.status), avatar: Icon(robot.connected ? Icons.circle : Icons.circle_outlined, size: 12, color: robot.connected ? Colors.green : Colors.grey)),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(style: FilledButton.styleFrom(backgroundColor: const Color(0xffffe7e9), foregroundColor: const Color(0xffb42332)), onPressed: ref.read(robotProvider.notifier).emergencyStop, icon: const Icon(Icons.emergency), label: const Text('Parar')),
        const SizedBox(width: 12),
      ]),
      body: Row(children: [
        NavigationRail(selectedIndex: index, labelType: NavigationRailLabelType.all, onDestinationSelected: (value) => setState(() => index = value), destinations: const [
          NavigationRailDestination(icon: Icon(Icons.control_camera_outlined), selectedIcon: Icon(Icons.control_camera), label: Text('Control')),
          NavigationRailDestination(icon: Icon(Icons.gps_fixed), label: Text('Mover TCP')),
          NavigationRailDestination(icon: Icon(Icons.playlist_play), label: Text('Programas')),
          NavigationRailDestination(icon: Icon(Icons.gesture), label: Text('Enseñar')),
          NavigationRailDestination(icon: Icon(Icons.tune), label: Text('Configurar')),
        ]),
        const VerticalDivider(width: 1),
        Expanded(child: Padding(padding: const EdgeInsets.all(24), child: page)),
      ]),
    );
  }

  Widget _tcpPanel() => LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Mueve la punta de la garra', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
    const Text('La app enviará una meta. El ESP32 siempre valida límites y seguridad.'),
    const SizedBox(height: 24),
    Container(height: 260, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xffe6f6ff), Color(0xfff3edff), Color(0xffffefeb)])), child: const Center(child: Icon(Icons.precision_manufacturing_outlined, size: 112, color: Color(0xff2768f4)))),
    const SizedBox(height: 22),
    Wrap(spacing: 12, runSpacing: 12, children: [_coordinate('X', x), _coordinate('Y', y), _coordinate('Z', z), FilledButton.icon(onPressed: () => ref.read(robotProvider.notifier).setTarget(double.tryParse(x.text) ?? 0, double.tryParse(y.text) ?? 0, double.tryParse(z.text) ?? 0), icon: const Icon(Icons.send), label: const Text('Mover a posición'))]),
    const SizedBox(height: 24),
    OutlinedButton.icon(onPressed: ref.read(robotProvider.notifier).goHome, icon: const Icon(Icons.home_outlined), label: const Text('Ir a home')),
  ])));

  Widget _coordinate(String label, TextEditingController controller) => SizedBox(width: 130, child: TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '$label (mm)', suffixText: 'mm', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))));
  Widget _placeholder(String title) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.construction_rounded, size: 60, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12), Text('$title en construcción', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 4), const Text('Esta pantalla se conectará a los casos de uso del dominio.'),]));
}
