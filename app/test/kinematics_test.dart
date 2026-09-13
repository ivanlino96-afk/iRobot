import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:airobot_kinematics/airobot_kinematics.dart';
import 'package:airobot/domain/models.dart';

void main() {
  late NativeKinematics math;
  late RobotProfile p;
  setUpAll(() {
    math = NativeKinematics();
    final raw = File('assets/profile.simulation.json').readAsStringSync();
    p = RobotProfile(raw, sha256.convert(utf8.encode(raw)).toString());
  });
  test('Same native solver validates home and rejects unreachable pose', () {
    expect(math.validate(p.nativeValues), isTrue);
    expect(
      math.plan(p.nativeValues, p.home, [0, 0, 0], 10),
      orderedEquals(p.home),
    );
    expect(
      () => math.plan(p.nativeValues, p.home, [99999, 0, 0], 10),
      throwsStateError,
    );
  });
  test('J2 coupled channel limits reject entire move', () {
    final q = List<double>.of(p.home)..[1] = 100;
    expect(math.path(p.nativeValues, p.home, q, 10), isFalse);
  });
  test(
    'Native simulation latch survives new movement and reset needs reference',
    () {
      final c = NativeRobot(math, p.nativeValues);
      expect(c.command(2, null, 10, 1), isFalse);
      expect(c.command(1, p.home, 10, 1), isTrue);
      expect(c.command(2, null, 10, 1), isTrue);
      final q = List<double>.of(p.home)..[1] = 10;
      expect(c.command(7, q, 10, 1), isTrue);
      c.tick(21, true);
      c.command(3, null, 10, 22);
      final before = c.tick(41, true);
      expect(before.$1, 8);
      expect(c.command(7, q, 10, 42), isFalse);
      expect(c.tick(61, true).$2, before.$2);
      expect(c.command(4, null, 10, 62), isTrue);
      expect(c.command(2, null, 10, 63), isFalse);
      c.dispose();
    },
  );
  test('Malformed coordinate values are rejected', () {
    expect(
      () => RobotProfile.numbers([double.nan, 0, 0], 3),
      throwsFormatException,
    );
    expect(
      () => ProgramStep(tcp: [0, 0, 0], gripper: 0, speed: 0, pauseMs: 0),
      throwsFormatException,
    );
  });
}
