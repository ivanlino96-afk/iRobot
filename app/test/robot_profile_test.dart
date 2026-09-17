import 'dart:convert';
import 'package:airobot/domain/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exposes velocity, acceleration and tool offset from the profile', () async {
    final raw = await rootBundle.loadString('assets/profile.simulation.json');
    final profile = RobotProfile(raw, sha256.convert(utf8.encode(raw)).toString());
    expect(profile.velocity, hasLength(7));
    expect(profile.acceleration, hasLength(7));
    expect(profile.tool, hasLength(3));
    expect(profile.tool, [0, 0, 140]);
  });
}
