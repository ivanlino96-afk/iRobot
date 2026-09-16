import Ajv from "ajv";
import { readFileSync } from "node:fs";
const ajv = new Ajv({ allErrors: true, strict: true });
const check = ajv.compile(
  JSON.parse(
    readFileSync(
      new URL("../../contracts/profile.schema.json", import.meta.url),
    ),
  ),
);
export function profileValid(p) {
  if (!check(p)) return false;
  const used = new Set(),
    counts = Array(7).fill(0);
  for (const s of p.servos) {
    if (
      used.has(s.pcaChannel) ||
      s.min >= s.max ||
      s.pulseMin >= s.pulseMax ||
      s.ratio === 0
    )
      return false;
    used.add(s.pcaChannel);
    counts[s.joint]++;
    const home = s.zero + s.offset + s.ratio * p.home[s.joint];
    if (home < s.min || home > s.max) return false;
  }
  if (counts.some((v, i) => v !== (i === 1 ? 2 : 1))) return false;
  return (
    p.home.every(
      (h, i) =>
        p.minimum[i] < p.maximum[i] && h >= p.minimum[i] && h <= p.maximum[i],
    ) &&
    p.axes.every((a) => Math.abs(Math.hypot(...a.axis) - 1) < 1e-6) &&
    p.boxes.every((b) => b.min.every((v, i) => v < b.max[i]))
  );
}
export function programValid(p) {
  return (
    p &&
    Object.keys(p).every((k) =>
      [
        "profileVersion",
        "profileHash",
        "homeRevision",
        "kinematicsVersion",
        "steps",
        "orientation",
        "confirmed",
      ].includes(k),
    ) &&
    Number.isInteger(p.profileVersion) &&
    typeof p.profileHash === "string" &&
    p.profileHash.length === 64 &&
    Number.isInteger(p.homeRevision) &&
    p.kinematicsVersion === "ik-dls-1" &&
    p.orientation === "home" &&
    p.confirmed === true &&
    Array.isArray(p.steps) &&
    p.steps.length > 0 &&
    p.steps.length <= 32 &&
    p.steps.every(
      (s) =>
        Object.keys(s).every((k) =>
          ["tcp", "gripperDegrees", "speedPercent", "pauseMs"].includes(k),
        ) &&
        Array.isArray(s.tcp) &&
        s.tcp.length === 3 &&
        s.tcp.every(Number.isFinite) &&
        Number.isFinite(s.gripperDegrees) &&
        Number.isInteger(s.speedPercent) &&
        s.speedPercent >= 1 &&
        s.speedPercent <= 100 &&
        Number.isInteger(s.pauseMs) &&
        s.pauseMs >= 0 &&
        s.pauseMs <= 600000,
    )
  );
}
