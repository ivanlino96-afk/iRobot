#pragma once
#include <math.h>

namespace bench {
struct Calibration {
  float minimum = 0, maximum = 180, offset = 0;
  int pulseMin = 150, pulseMax = 600;
  bool confirmed = false;
};
inline bool valid(const Calibration &c) {
  return isfinite(c.minimum) && isfinite(c.maximum) && isfinite(c.offset) &&
         c.minimum >= 0 && c.maximum <= 180 && c.minimum < c.maximum &&
         fabsf(c.offset) <= 90 && c.pulseMin >= 80 && c.pulseMax <= 650 &&
         c.pulseMin < c.pulseMax;
}
// Calibration limits refer to each physical servo AFTER its offset.
inline float servoAngle(int channel, float base, const Calibration &c) {
  return (channel == 2 ? 180.0f - base : base) + c.offset;
}
inline bool accepts(int channel, float base, const Calibration &c) {
  const float a = servoAngle(channel, base, c);
  return valid(c) && isfinite(base) && base >= 0 && base <= 180 &&
         a >= c.minimum && a <= c.maximum;
}
inline int pulse(int channel, float base, const Calibration &c) {
  return (int)lroundf(c.pulseMin + servoAngle(channel, base, c) / 180.0f *
                                       (c.pulseMax - c.pulseMin));
}
inline float duration(float from, float to, float velocity,
                      float acceleration) {
  const float d = fabsf(to - from);
  return fmaxf(0.1f,
               fmaxf(1.875f * d / velocity, sqrtf(5.774f * d / acceleration)));
}
inline float interpolate(float from, float to, float u) {
  u = fmaxf(0, fminf(1, u));
  return from + (to - from) * u * u * u * (10 + u * (-15 + 6 * u));
}
} // namespace bench
