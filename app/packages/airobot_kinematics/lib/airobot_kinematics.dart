import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

class NativeKinematics {
  NativeKinematics({DynamicLibrary? library})
    : lib =
          library ??
          (Platform.isIOS
              ? DynamicLibrary.process()
              : DynamicLibrary.open(
                  Platform.environment['AIROBOT_NATIVE_LIB'] ??
                      'libairobot_kinematics.so',
                ));
  final DynamicLibrary lib;
  Pointer<Double> _copy(List<double> a) {
    final p = calloc<Double>(a.length);
    p.asTypedList(a.length).setAll(0, a);
    return p;
  }

  bool validate(List<double> profile) {
    final p = _copy(profile);
    try {
      return lib.lookupFunction<
            Int32 Function(Pointer<Double>),
            int Function(Pointer<Double>)
          >('airobot_validate')(p) ==
          1;
    } finally {
      calloc.free(p);
    }
  }

  List<double> plan(
    List<double> profile,
    List<double> from,
    List<double> tcp,
    int speed,
  ) {
    final p = _copy(profile),
        a = _copy(from),
        b = _copy(tcp),
        out = calloc<Double>(7);
    try {
      final fn = lib
          .lookupFunction<
            Int32 Function(
              Pointer<Double>,
              Pointer<Double>,
              Pointer<Double>,
              Int32,
              Pointer<Double>,
            ),
            int Function(
              Pointer<Double>,
              Pointer<Double>,
              Pointer<Double>,
              int,
              Pointer<Double>,
            )
          >('airobot_plan');
      if (fn(p, a, b, speed, out) != 1) {
        throw StateError(
          'Destino u orientación fuera de alcance, límites o trayectoria válida',
        );
      }
      return List.of(out.asTypedList(7));
    } finally {
      calloc.free(p);
      calloc.free(a);
      calloc.free(b);
      calloc.free(out);
    }
  }

  bool path(
    List<double> profile,
    List<double> from,
    List<double> to,
    int speed,
  ) {
    final p = _copy(profile), a = _copy(from), b = _copy(to);
    try {
      return lib.lookupFunction<
            Int32 Function(
              Pointer<Double>,
              Pointer<Double>,
              Pointer<Double>,
              Int32,
            ),
            int Function(Pointer<Double>, Pointer<Double>, Pointer<Double>, int)
          >('airobot_path')(p, a, b, speed) ==
          1;
    } finally {
      calloc.free(p);
      calloc.free(a);
      calloc.free(b);
    }
  }

  List<double> forward(List<double> profile, List<double> from) {
    final p = _copy(profile), a = _copy(from), out = calloc<Double>(3);
    try {
      if (lib.lookupFunction<
            Int32 Function(Pointer<Double>, Pointer<Double>, Pointer<Double>),
            int Function(Pointer<Double>, Pointer<Double>, Pointer<Double>)
          >('airobot_forward')(p, a, out) !=
          1) {
        throw StateError('Referencia o geometría inválida');
      }
      return List.of(out.asTypedList(3));
    } finally {
      calloc.free(p);
      calloc.free(a);
      calloc.free(out);
    }
  }
}

class NativeRobot {
  NativeRobot(this.kinematics, List<double> profile) {
    final p = calloc<Double>(profile.length);
    p.asTypedList(profile.length).setAll(0, profile);
    handle = kinematics.lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Double>),
          Pointer<Void> Function(Pointer<Double>)
        >('airobot_create')(p);
    calloc.free(p);
  }
  final NativeKinematics kinematics;
  late Pointer<Void> handle;
  bool command(int type, List<double>? values, int speed, int now) {
    final p = calloc<Double>(7);
    if (values != null) p.asTypedList(7).setAll(0, values);
    try {
      return kinematics.lib.lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Double>, Int32, Int64),
            int Function(Pointer<Void>, int, Pointer<Double>, int, int)
          >('airobot_command')(handle, type, p, speed, now) ==
          1;
    } finally {
      calloc.free(p);
    }
  }

  bool program(List<List<double>> steps, int now) {
    final p = calloc<Double>(steps.length * 9);
    p.asTypedList(steps.length * 9).setAll(0, steps.expand((e) => e));
    try {
      return kinematics.lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Double>, Int32, Int64),
            int Function(Pointer<Void>, Pointer<Double>, int, int)
          >('airobot_program')(handle, p, steps.length, now) ==
          1;
    } finally {
      calloc.free(p);
    }
  }

  (int, List<double>, bool) tick(int now, bool connected) {
    final p = calloc<Double>(8);
    try {
      final state = kinematics.lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int64, Int32, Pointer<Double>),
            int Function(Pointer<Void>, int, int, Pointer<Double>)
          >('airobot_tick')(handle, now, connected ? 1 : 0, p);
      return (state, List.of(p.asTypedList(7)), p[7] != 0);
    } finally {
      calloc.free(p);
    }
  }

  void dispose() =>
      kinematics.lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('airobot_destroy')(handle);
}
