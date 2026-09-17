import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/data/mqtt_robot_repository.dart';

void main() {
  test('starts at half a second and doubles with each attempt', () {
    expect(backoffDelay(0), const Duration(milliseconds: 500));
    expect(backoffDelay(1), const Duration(milliseconds: 1000));
    expect(backoffDelay(2), const Duration(milliseconds: 2000));
    expect(backoffDelay(3), const Duration(milliseconds: 4000));
  });

  test('caps at thirty seconds no matter how many attempts', () {
    expect(backoffDelay(10), const Duration(seconds: 30));
    expect(backoffDelay(100), const Duration(seconds: 30));
  });
}
