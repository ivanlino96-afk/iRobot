import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../domain/models.dart';
import 'robot_view_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.model});
  final RobotViewModel? model;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final RobotViewModel vm;
  int page = 0, speed = 10, joint = 0;
  final angle = TextEditingController(text: '0'),
      px = TextEditingController(text: '0'),
      py = TextEditingController(text: '0'),
      pz = TextEditingController(text: '0'),
      grip = TextEditingController(text: '0'),
      pause = TextEditingController(text: '500'),
      programName = TextEditingController();
  final labels = ['Control', 'Mover TCP', 'Programas', 'Enseñar', 'Configurar'];
  final icons = [
    Icons.tune,
    Icons.open_with,
    Icons.playlist_play,
    Icons.add_location_alt_outlined,
    Icons.settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    vm = widget.model ?? RobotViewModel();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.model == null) vm.dispose();
    for (final c in [angle, px, py, pz, grip, pause, programName]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      vm.suspend();
    }
  }

  double value(TextEditingController c) {
    final v = double.tryParse(c.text);
    if (v == null || !v.isFinite) {
      throw const FormatException('Introduce un número válido');
    }
    return v;
  }

  int pauseValue() {
    final v = int.tryParse(pause.text);
    if (v == null || v < 0 || v > 600000) {
      throw const FormatException('Pausa de 0 a 600000 ms');
    }
    return v;
  }

  void run(Future<void> Function() fn) => vm.act(fn);
  Widget field(String label, TextEditingController c, {double width = 140}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(labelText: label),
        ),
      );
  Widget card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffe6e6e6)),
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
  Widget title(String text, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: vm,
    builder: (context, _) => LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 800;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'AiRobot',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -.7,
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => connection(),
                icon: Icon(
                  vm.snapshot.connected ? Icons.sensors : Icons.sensors_off,
                  size: 18,
                ),
                label: Text(vm.snapshot.connected ? vm.robotId : 'Conectar'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: page,
                  onDestinationSelected: (v) => setState(() => page = v),
                  destinations: [
                    for (int i = 0; i < 5; i++)
                      NavigationDestination(
                        icon: Icon(icons[i]),
                        label: labels[i],
                      ),
                  ],
                ),
          body: Column(
            children: [
              Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        vm.snapshot.simulation
                            ? 'SIMULADOR · ${vm.snapshot.state}'
                            : vm.snapshot.state,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: vm.snapshot.connected
                            ? () => run(() => vm.send('stop'))
                            : null,
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('Parar'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xffb3261e),
                        ),
                        onPressed: vm.snapshot.connected
                            ? () async {
                                try {
                                  await vm.send('emergencyStop');
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Bloquear movimiento'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (wide)
                      NavigationRail(
                        selectedIndex: page,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: (v) => setState(() => page = v),
                        destinations: [
                          for (int i = 0; i < 5; i++)
                            NavigationRailDestination(
                              icon: Icon(icons[i]),
                              label: Text(labels[i]),
                            ),
                        ],
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(wide ? 36 : 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (vm.busy)
                                  const LinearProgressIndicator(minHeight: 2),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Text(
                                    vm.message,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                switch (page) {
                                  0 => control(),
                                  1 => tcp(),
                                  2 => programs(),
                                  3 => teach(),
                                  _ => settings(),
                                },
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  Widget control() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffc6e1f7), Color(0xffc8c6f6), Color(0xffe3e0f4)],
          ),
        ),
        child: Column(
          children: [
            const Icon(Icons.precision_manufacturing_outlined, size: 48),
            const SizedBox(height: 18),
            Text(
              'Tu robot.\nCada movimiento, bajo control.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'Mueve, enseña y crea secuencias.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: vm.busy
                  ? null
                  : () => vm.repository == null ? run(vm.demo) : reference(),
              icon: Icon(
                vm.repository == null
                    ? Icons.science_outlined
                    : Icons.my_location,
              ),
              label: Text(
                vm.repository == null
                    ? 'Explorar simulador'
                    : 'Confirmar referencia',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (vm.repository == null)
        const Text(
          'El simulador funciona sin conectar hardware. Sus datos mecánicos son de prueba.',
        ),
      if (vm.repository != null) ...[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed:
                  vm.snapshot.state == 'BOOT_LOCKED' && vm.snapshot.reference
                  ? () => run(() => vm.send('enable'))
                  : null,
              child: const Text('Habilitar control'),
            ),
            OutlinedButton(
              onPressed: vm.snapshot.state == 'HOLD'
                  ? () => run(() => vm.send('acknowledgeHold'))
                  : null,
              child: const Text('Reconocer parada'),
            ),
            OutlinedButton(
              onPressed: ['ESTOP_LATCHED', 'FAULT'].contains(vm.snapshot.state)
                  ? () => run(vm.reset)
                  : null,
              child: const Text('Rearmar bloqueo'),
            ),
            OutlinedButton.icon(
              onPressed: vm.canMove
                  ? () => run(() => vm.send('goHome', {'speedPercent': speed}))
                  : null,
              icon: const Icon(Icons.home_outlined),
              label: const Text('Ir a home'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(
                'Control articular',
                'J2 coordina sus dos servos. Los valores son consignas, no posiciones medidas.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownMenu<int>(
                    initialSelection: joint,
                    label: const Text('Articulación'),
                    onSelected: (v) => setState(() => joint = v!),
                    dropdownMenuEntries: [
                      for (int j = 0; j < 7; j++)
                        DropdownMenuEntry(
                          value: j,
                          label: 'J${j + 1}${j == 6 ? ' · Garra' : ''}',
                        ),
                    ],
                  ),
                  field('Objetivo (°)', angle),
                  FilledButton(
                    onPressed: vm.canMove
                        ? () => run(
                            () => vm.moveJoint(joint, value(angle), speed),
                          )
                        : null,
                    child: const Text('Mover articulación'),
                  ),
                ],
              ),
              velocity(),
              const Divider(),
              Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  for (int j = 0; j < 7; j++)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'J${j + 1}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${vm.snapshot.joints[j].toStringAsFixed(1)}°',
                          style: const TextStyle(fontSize: 22),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (vm.snapshot.simulation)
          OutlinedButton(
            onPressed: () => run(() => vm.send('disconnectTest')),
            child: const Text('Probar pérdida de control'),
          ),
      ],
    ],
  );
  Widget velocity() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(
        'Velocidad · $speed% de los límites calibrados',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Slider(
        value: speed.toDouble(),
        min: 1,
        max: 100,
        divisions: 99,
        label: '$speed%',
        onChanged: (v) => setState(() => speed = v.round()),
      ),
    ],
  );
  Widget tcp() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        '¿A dónde quieres moverlo?',
        'Coordenadas en milímetros respecto a home. Se mantiene la orientación de la garra definida en home.',
      ),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                field('X · mm', px),
                field('Y · mm', py),
                field('Z · mm', pz),
                field('Garra · °', grip),
              ],
            ),
            velocity(),
            FilledButton.icon(
              onPressed: vm.canMove && vm.profile?.geometry == true
                  ? () => run(
                      () => vm.tcp(
                        [value(px), value(py), value(pz)],
                        speed,
                        value(grip),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Validar y mover'),
            ),
            const SizedBox(height: 16),
            Text(
              vm.profile?.geometry == true
                  ? 'Trayectoria articular punto a punto. No implica una línea recta del TCP.'
                  : 'Movimiento TCP bloqueado hasta validar geometría y calibración.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TCP estimado desde consignas'),
            const SizedBox(height: 12),
            Text(
              vm.snapshot.tcp?.map((v) => v.toStringAsFixed(1)).join('  /  ') ??
                  'Referencia desconocida',
              style: const TextStyle(fontSize: 28, letterSpacing: -.7),
            ),
            const Text('X / Y / Z · mm'),
          ],
        ),
      ),
    ],
  );
  Widget teach() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Enseña una secuencia',
        'Lleva el robot a cada punto con los controles y guarda su consigna. No se registra movimiento manual del brazo.',
      ),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                field('Pausa · ms', pause),
                FilledButton.icon(
                  onPressed: vm.snapshot.reference
                      ? () => run(() async => vm.teach(speed, pauseValue()))
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Guardar punto actual'),
                ),
              ],
            ),
            velocity(),
            const SizedBox(height: 12),
            for (int i = 0; i < vm.steps.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text('${i + 1}'.padLeft(2, '0')),
                title: Text(
                  vm.steps[i].tcp.map((x) => x.toStringAsFixed(1)).join(' / '),
                ),
                subtitle: Text(
                  '${vm.steps[i].speed}% · ${vm.steps[i].pauseMs} ms · garra ${vm.steps[i].gripper}°',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Editar paso',
                      onPressed: () => editStep(i),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Subir',
                      onPressed: i > 0
                          ? () => setState(() {
                              final s = vm.steps.removeAt(i);
                              vm.steps.insert(i - 1, s);
                            })
                          : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Eliminar paso',
                      onPressed: () => setState(() => vm.steps.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (vm.steps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Tu primer punto empieza con un movimiento.'),
              ),
            TextField(
              controller: programName,
              decoration: const InputDecoration(
                labelText: 'Nombre del programa',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: vm.steps.isNotEmpty && !vm.busy
                  ? () => run(() => vm.save(programName.text))
                  : null,
              child: Text(
                vm.snapshot.simulation
                    ? 'Guardar en esta simulación'
                    : 'Guardar en la nube',
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget programs() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Tus programas',
        'Cada secuencia conserva el perfil y la referencia con los que se creó.',
      ),
      OutlinedButton.icon(
        onPressed: vm.repository != null ? () => run(vm.loadPrograms) : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar'),
      ),
      const SizedBox(height: 16),
      if (vm.saved.isEmpty)
        card(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aún no hay programas. Abre Enseñar para crear el primero.',
            ),
          ),
        ),
      for (final p in vm.saved)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'], style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${(p['body']['steps'] as List).length} puntos · ${p['needsRevalidation'] == true ? 'Requiere revalidación' : 'Perfil compatible'}',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: vm.canMove && p['needsRevalidation'] != true
                          ? () => run(() => vm.run(p))
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Ejecutar'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        vm.editProgram(p);
                        programName.text = p['name'];
                        setState(() => page = 3);
                      },
                      child: const Text('Editar copia'),
                    ),
                    if (p['needsRevalidation'] == true)
                      OutlinedButton(
                        onPressed: vm.snapshot.reference
                            ? () => confirmRevalidation(p)
                            : null,
                        child: const Text('Revalidar revisión'),
                      ),
                    IconButton(
                      tooltip: 'Eliminar programa',
                      onPressed: () => run(() async {
                        await vm.repository!.deleteProgram(p['id']);
                        await vm.loadPrograms();
                      }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Configuración del robot', 'XIAO ESP32-C3 · SDA GPIO6 · SCL GPIO7'),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vm.profile == null
                  ? 'Sin perfil activo'
                  : 'Perfil v${vm.profile!.version}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              vm.profile?.calibrated == true
                  ? 'Calibración declarada en el perfil'
                  : 'Calibración pendiente',
            ),
            Text(
              vm.profile?.geometry == true
                  ? 'Geometría validada'
                  : 'Geometría pendiente',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: vm.repository != null ? profileEditor : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar perfil mecánico'),
            ),
            const SizedBox(height: 20),
            if (vm.profile != null)
              for (final s in vm.profile!.json['servos'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Canal ${s['pcaChannel']} → J${s['joint'] + 1} · ${s['min']}–${s['max']}° · offset ${s['offset']}°',
                  ),
                ),
            const Divider(),
            const Text(
              'Calibración individual: procedimiento por USB, con el brazo soportado. Consulta la guía de instalación y pruebas.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Bloquear movimiento es una parada por software. No corta la alimentación de los servos.',
              style: TextStyle(color: Color(0xff5d5d5d)),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> connection() async {
    final url = TextEditingController(
          text: const String.fromEnvironment(
            'API_URL',
            defaultValue: 'https://robot.example.com',
          ),
        ),
        email = TextEditingController(),
        password = TextEditingController(),
        qr = TextEditingController();
    bool register = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: const Text('Conecta tu robot'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(
                      labelText: 'URL HTTPS de la API',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña · mínimo 12 caracteres',
                    ),
                  ),
                  CheckboxListTile(
                    value: register,
                    onChanged: (v) => change(() => register = v!),
                    title: const Text('Crear cuenta'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await vm.act(
                        () => vm.login(
                          url.text,
                          email.text,
                          password.text,
                          register,
                        ),
                      );
                      if (ctx.mounted) change(() {});
                    },
                    child: const Text('Iniciar sesión'),
                  ),
                  const SizedBox(height: 12),
                  Text(vm.message),
                  if (vm.api?.token != null) ...[
                    TextField(
                      controller: qr,
                      decoration: const InputDecoration(
                        labelText: 'Contenido del QR',
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final result = await Navigator.of(ctx).push<String>(
                              MaterialPageRoute(
                                builder: (_) => const ScanPage(),
                              ),
                            );
                            if (result != null) {
                              qr.text = result;
                            }
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Escanear'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await vm.act(() => vm.pair(qr.text));
                            if (ctx.mounted) change(() {});
                          },
                          child: const Text('Vincular'),
                        ),
                      ],
                    ),
                    for (final id in vm.robots)
                      ListTile(
                        title: Text(id),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          Navigator.pop(ctx);
                          run(() => vm.connect(id));
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                run(vm.demo);
              },
              child: const Text('Usar simulador'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
    for (final c in [url, email, password, qr]) {
      c.dispose();
    }
  }

  Future<void> reference() async {
    final controllers = List.generate(
      7,
      (i) => TextEditingController(
        text: vm.snapshot.simulation ? vm.profile?.home[i].toString() : '',
      ),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar referencia'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Introduce los ángulos del montaje observado. Registrar la referencia no mueve el brazo ni mide su posición.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (int i = 0; i < 7; i++)
                      field('J${i + 1} · °', controllers[i]),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              run(() => vm.reference(controllers.map(value).toList()));
              Navigator.pop(ctx);
            },
            child: const Text('Confirmar ángulos'),
          ),
        ],
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
  }

  Future<void> profileEditor() async {
    final editor = TextEditingController(
      text: vm.profile == null
          ? '{}'
          : const JsonEncoder.withIndent('  ').convert(vm.profile!.json),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perfil mecánico versionado'),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Incrementa version para activar cambios. Los programas anteriores requieren revalidación. No marques calibrado sin completar las pruebas.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: editor,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(labelText: 'Perfil JSON'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final raw = editor.text;
              Navigator.pop(ctx);
              run(() => vm.applyProfile(raw));
            },
            child: const Text('Validar y activar'),
          ),
        ],
      ),
    );
    editor.dispose();
  }

  Future<void> confirmRevalidation(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revalidar con el perfil actual'),
        content: const Text(
          'Los mismos puntos pueden producir movimientos distintos tras cambiar home o geometría. Se validarán de nuevo y se guardará una revisión; no se ejecutará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar revalidación'),
          ),
        ],
      ),
    );
    if (ok == true) run(() => vm.revalidate(p));
  }

  Future<void> editStep(int i) async {
    final controllers = [
      for (final v in [
        ...vm.steps[i].tcp,
        vm.steps[i].gripper,
        vm.steps[i].speed,
        vm.steps[i].pauseMs,
      ])
        TextEditingController(text: '$v'),
    ];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar punto ${i + 1}'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (int j = 0; j < 6; j++)
                field(
                  [
                    'X mm',
                    'Y mm',
                    'Z mm',
                    'Garra °',
                    'Velocidad %',
                    'Pausa ms',
                  ][j],
                  controllers[j],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              run(() async {
                final vals = controllers.map(value).toList();
                if (vals[4] != vals[4].roundToDouble() ||
                    vals[5] != vals[5].roundToDouble()) {
                  throw const FormatException(
                    'Velocidad y pausa deben ser enteros',
                  );
                }
                vm.steps[i] = ProgramStep(
                  tcp: vals.take(3).toList(),
                  gripper: vals[3],
                  speed: vals[4].toInt(),
                  pauseMs: vals[5].toInt(),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanea el QR del robot')),
    body: MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (!done && value != null) {
          done = true;
          Navigator.pop(context, value);
        }
      },
    ),
  );
}
