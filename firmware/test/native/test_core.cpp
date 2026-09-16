#include "core.hpp"
#include <cassert>
#include <iostream>
using namespace airobot;
Profile fixture() {
  Profile p;
  p.version = 1;
  p.hash = std::string(64, 'a');
  p.calibrated = p.geometryValidated = true;
  p.heartbeatMs = 1000;
  p.maxTickMs = 100;
  p.minimum.fill(-80);
  p.maximum.fill(80);
  p.home.fill(0);
  p.velocity.fill(15);
  p.acceleration.fill(30);
  int joints[] = {0, 1, 1, 2, 3, 4, 5, 6};
  for (int i = 0; i < 8; i++)
    p.servos[i] = {joints[i], i, 90, 0, i == 2 ? -1. : 1., 5, 175, 600, 2400};
  for (int i = 0; i < 6; i++)
    p.axes[i] = {{0, 0, 50}, i == 0 || i == 5 ? Vec{0, 0, 1} : Vec{0, 1, 0}};
  p.tool = {0, 0, 140};
  return p;
}
int main() {
  auto p = fixture();
  assert(p.valid());
  auto bad = p;
  bad.servos[2].channel = 1;
  assert(!bad.valid());
  bad = p;
  bad.servos[2].max = 89;
  assert(!bad.valid());
  auto q = p.home;
  q[1] = 80;
  assert(p.legal(q));
  q[1] = 86;
  assert(!p.legal(q));
  q[0] = NAN;
  assert(!p.legal(q));
  Core c;
  assert(c.configure(p));
  assert(!c.enable(1));
  assert(c.reference(p.home));
  assert(c.enable(1));
  auto target = p.home;
  target[1] = 30;
  assert(c.run({{target, 20, 100}}, 1));
  for (int t = 21; t < 1000; t += 20) {
    c.beat(t);
    c.tick(t, true);
  }
  auto at = c.q;
  c.latch();
  for (int t = 1001; t < 2000; t += 20)
    c.tick(t, true);
  assert(c.q == at);
  assert(!c.run({{target, 10, 0}}, 2000));
  assert(c.reset());
  assert(!c.enable(2000));
  assert(c.reference(p.home));
  assert(c.enable(2001));
  assert(c.run({{target, 20, 0}, {p.home, 20, 0}}, 2001));
  for (int t = 2021; t < 2600; t += 20) {
    c.beat(t);
    c.tick(t, true);
  }
  c.tick(2601, false);
  assert(c.state == State::STOPPING);
  for (int t = 2621; t < 5000; t += 20)
    c.tick(t, false);
  assert(c.state == State::HOLD);
  auto held = c.q;
  assert(held[1] < 30);
  c.tick(5021, true);
  assert(c.q == held && c.state == State::HOLD);
  Replay r;
  r.open("one");
  assert(r.accept("A", 1, "x") == "ok");
  assert(r.accept("B", 2, "y") == "ok");
  assert(r.accept("A", 1, "x") == "duplicate:accepted");
  assert(r.accept("A", 3, "z") == "id-reused");
  assert(r.accept("C", 1, "q") == "sequence");
  for (int i = 3; i < 100; i++)
    assert(r.accept(std::to_string(i), i, "h") == "ok");
  assert(r.accept("A", 1, "x") == "sequence");
  Joints ik{};
  assert(inverse(p, {0, 0, 0}, p.home, 10, ik));
  assert(!inverse(p, {10000, 0, 0}, p.home, 10, ik));
  auto rotated = p.home;
  rotated[5] = 25;
  auto relative = sub(forward(p, rotated).position, forward(p, p.home).position);
  assert(inverse(p, relative, rotated, 10, ik, true));
  assert(orientationDistance(forward(p, ik).orientation, forward(p, rotated).orientation) < .001);
  assert(!inverse(p, {10000, 0, 0}, rotated, 10, ik, true));
  bad = p;
  bad.boxes.push_back({{-1, -1, 1}, {1, 1, 100}});
  assert(!pathLegal(bad, p.home, p.home));
  // Finite-difference limits on complete quintic trajectory.
  auto d = duration(p, p.home, target, 50);
  double prev = 0, vel = 0;
  for (double t = .001; t <= d; t += .001) {
    double now = interpolate(p.home, target, t / d)[1],
           nv = (now - prev) / .001;
    assert(fabs(nv) <= 7.501);
    assert(fabs((nv - vel) / .001) <= 30.01);
    prev = now;
    vel = nv;
  }
  std::cout << "Core: calibration, J2, limits, latch, replay, disconnect, IK "
               "and trajectory tests passed\n";
}
