#include "../../arduino/ServoBench/Motion.h"
#include <cassert>
#include <cstdio>
#include <initializer_list>
int main() {
  bench::Calibration c;
  assert(bench::valid(c));
  assert(bench::accepts(0, 90, c));
  for (int channel = 0; channel < 8; ++channel) {
    assert(bench::accepts(channel, 0, c));
    assert(bench::accepts(channel, 180, c));
    assert(!bench::accepts(channel, -1, c));
    assert(!bench::accepts(channel, 181, c));
  }
  assert(bench::pulse(1, 0, c) == 150);
  assert(bench::pulse(2, 0, c) == 600);
  assert(bench::pulse(1, 180, c) == 600);
  assert(bench::pulse(2, 180, c) == 150);
  assert(!bench::accepts(0, NAN, c));
  assert(bench::pulse(0, 90, c) == 375);
  assert(bench::servoAngle(1, 85, c) == 85);
  assert(bench::servoAngle(2, 85, c) == 95);
  c.offset = 3;
  assert(bench::servoAngle(2, 85, c) == 98);
  assert(!bench::accepts(2, 0, c)); // Partner exceeds its own upper limit.
  c.pulseMax = 4096;
  assert(!bench::valid(c));
  for (float end : {80.f, 100.f}) {
    const float t = bench::duration(90, end, 5, 10);
    float prev = 90, prevV = 0;
    const float dt = 0.02f;
    for (float elapsed = dt; elapsed < t; elapsed += dt) {
      float q = bench::interpolate(90, end, elapsed / t);
      float v = (q - prev) / dt;
      assert(fabsf(v) < 5.1f);
      assert(fabsf((v - prevV) / dt) < 10.2f);
      assert(q >= 80 && q <= 100);
      prev = q;
      prevV = v;
    }
    assert(bench::interpolate(90, end, 1) == end);
  }
  puts("Servo bench: limits, mirrored pair, offsets, pulses and velocity "
       "passed");
}
