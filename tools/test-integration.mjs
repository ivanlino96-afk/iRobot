import assert from "node:assert/strict";
import https from "node:https";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { resolve } from "node:path";
import mqtt from "../backend/node_modules/mqtt/build/index.js";
import pg from "../backend/node_modules/pg/lib/index.js";
import { Broker } from "../backend/src/broker.js";
import { random, hash } from "../backend/src/security.js";
import { localEnvironment } from "./local-env.mjs";
const env = localEnvironment(),
  ca = readFileSync(env.MQTT_CA),
  db = new pg.Pool({ connectionString: env.DATABASE_URL });
const broker = new Broker(env);
const id = "test-" + random().slice(0, 10),
  username = "robot-" + id,
  password = random(),
  pairToken = random(),
  dir = resolve(".build/" + id);
mkdirSync(dir, { recursive: true });
const canonical = JSON.stringify(
  JSON.parse(readFileSync("contracts/profile.simulation.json")),
);
writeFileSync(dir + "/profile.json", canonical);
let engine, device, appClient, timer, heartbeat;
let latest,
  apiToken,
  session,
  sequence = 0,
  ackMap = new Map();
function request(method, path, data) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      "https://localhost:18443" + path,
      {
        method,
        ca,
        headers: {
          "Content-Type": "application/json",
          ...(apiToken ? { Authorization: "Bearer " + apiToken } : {}),
        },
      },
      (res) => {
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(body) });
          } catch {
            reject(Error(`Unexpected HTTP ${res.statusCode}`));
          }
        });
      },
    );
    req.setTimeout(5000, () => req.destroy(Error("HTTP timeout")));
    req.on("error", reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}
async function until(predicate, message, timeout = 8000) {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeout) throw Error(message);
    await new Promise((r) => setTimeout(r, 30));
  }
}
function connect(user, pass) {
  const c = mqtt.connect(env.MQTT_URL, {
    username: user,
    password: pass,
    ca,
    rejectUnauthorized: true,
    clean: true,
    reconnectPeriod: 0,
  });
  return new Promise((resolve, reject) => {
    c.once("connect", () => resolve(c));
    c.once("error", reject);
  });
}
const clock = () => ({
  monoMs: Math.floor(performance.now()),
  epochMs: Date.now(),
});
async function order(type, payload = {}, options = {}) {
  const now = Date.now(),
    commandId = random();
  const c = {
    schemaVersion: 1,
    commandId,
    robotId: id,
    bootId: latest.bootId,
    authorization: session.authorization,
    controlSessionId: session.sessionId,
    sequence: ++sequence,
    createdAtEpochMs: now,
    expiresAtEpochMs: now + 4000,
    profileVersion: 1,
    profileHash: hash(canonical),
    kinematicsVersion: "ik-dls-1",
    type,
    payload,
    ...options,
  };
  const raw = JSON.stringify(c);
  const promise = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ackMap.delete(commandId);
      reject(Error("ACK timeout: " + type));
    }, 5000);
    ackMap.set(commandId, (a) => {
      clearTimeout(timeout);
      resolve(a);
    });
  });
  appClient.publish(
    `airobot/v1/robots/${id}/${type === "emergencyStop" ? "emergency" : "command"}`,
    raw,
    { qos: 1, retain: false },
  );
  return promise;
}
async function open(scope = "control") {
  if (appClient) await appClient.endAsync();
  await request("DELETE", `/robots/${id}/session`);
  let r = await request("POST", `/robots/${id}/session`, {
    bootId: latest.bootId,
    scope,
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  session = r.body;
  sequence = 0;
  appClient = await connect(session.mqtt.username, session.mqtt.password);
  appClient.on("message", (topic, raw) => {
    const a = JSON.parse(raw);
    ackMap.get(a.commandId)?.(a);
  });
  await appClient.subscribeAsync(`airobot/v1/robots/${id}/ack`, { qos: 1 });
  assert.equal((await order("openSession")).status, "accepted");
}
try {
  await until(() => broker.client.connected, "Admin MQTT unavailable");
  assert.equal((await request("GET", "/health")).status, 200);
  await db.query(
    "INSERT INTO robots(id,pairing_hash,pairing_expires) VALUES($1,$2,$3)",
    [id, hash(pairToken), Date.now() + 60000],
  );
  await broker.grant(username, password, id, 0, true);
  let r = await request("POST", "/auth/register", {
    email: id + "@example.test",
    password: random(),
  });
  assert.equal(r.status, 201);
  apiToken = r.body.token;
  assert.equal(
    (await request("POST", "/pair", { robotId: id, token: pairToken })).status,
    200,
  );
  assert.equal(
    (await request("POST", "/pair", { robotId: id, token: pairToken })).status,
    409,
  );
  assert.equal(
    (await request("POST", `/robots/${id}/profile`, JSON.parse(canonical)))
      .status,
    201,
  );
  device = await connect(username, password);
  const root = `airobot/v1/robots/${id}/`;
  await device.subscribeAsync(
    ["command", "emergency", "config"].map((s) => root + s),
    { qos: 1 },
  );
  engine = spawn(
    resolve(".build/simulator"),
    [id, dir + "/profile.json", env.PUBLIC_KEY, dir],
    { stdio: ["pipe", "pipe", "inherit"] },
  );
  device.on("message", (topic, raw, packet) =>
    engine.stdin.write(
      JSON.stringify({
        kind: "command",
        raw: raw.toString(),
        retained: packet.retain,
        emergency: topic === root + "emergency",
        ...clock(),
      }) + "\n",
    ),
  );
  createInterface({ input: engine.stdout }).on("line", (line) => {
    const m = JSON.parse(line);
    if (m.topic === "state") latest = m.payload;
    device.publish(root + m.topic, JSON.stringify(m.payload), {
      qos: 1,
      retain: m.topic === "state",
    });
  });
  timer = setInterval(
    () =>
      engine.stdin.write(
        JSON.stringify({
          kind: "tick",
          connected: device.connected,
          ...clock(),
        }) + "\n",
      ),
    20,
  );
  await until(() => latest, "Simulator state unavailable");
  await new Promise((r) => setTimeout(r, 300));
  let state = await request("GET", `/robots/${id}/state`);
  assert.equal(state.status, 200, JSON.stringify(state.body));
  await open();
  heartbeat = setInterval(() => order("heartbeat").catch(() => {}), 250);
  assert.equal(
    (
      await order("confirmReference", {
        jointDegrees: Array(7).fill(0),
        operatorConfirmed: true,
      })
    ).status,
    "accepted",
  );
  assert.equal((await order("enable")).status, "accepted");
  assert.equal(
    (await order("moveJoint", { joint: 256, degrees: 10, speedPercent: 10 }))
      .status,
    "rejected",
  );
  assert.equal(
    (await order("moveJoint", { joint: 1, degrees: 20, speedPercent: 10 }))
      .status,
    "accepted",
  );
  await until(() => latest.state === "EXECUTING", "Move did not start");
  assert.equal((await order("emergencyStop")).status, "accepted");
  clearInterval(heartbeat);
  await until(() => latest.state === "ESTOP_LATCHED", "Latch failed");
  const held = [...latest.targetJointDegrees];
  await new Promise((r) => setTimeout(r, 200));
  assert.deepEqual(latest.targetJointDegrees, held);
  await open("recovery");
  assert.equal(
    (
      await order("resetLatch", {
        latchId: latest.latchId,
        resetNonce: "wrong",
      })
    ).status,
    "rejected",
  );
  assert.equal(
    (
      await order("resetLatch", {
        latchId: latest.latchId,
        resetNonce: latest.resetNonce,
      })
    ).status,
    "accepted",
  );
  await until(() => latest.state === "BOOT_LOCKED", "Reset must stay locked");
  await open();
  assert.equal(
    (
      await order("confirmReference", {
        jointDegrees: held,
        operatorConfirmed: true,
      })
    ).status,
    "accepted",
  );
  assert.equal((await order("enable")).status, "accepted");
  assert.equal(
    (await order("moveJoint", { joint: 1, degrees: 10, speedPercent: 10 }))
      .status,
    "accepted",
  );
  await until(
    () => latest.state === "HOLD",
    "Heartbeat loss must stop and hold",
    5000,
  );
  assert(latest.targetJointDegrees[1] < 10);
  // This stage allows authenticated clients to subscribe across robots.
  const shared = await appClient.subscribeAsync(
    "airobot/v1/robots/other/state",
    { qos: 1 },
  );
  assert(shared.every((g) => g.qos === 1));
  console.log(
    "PASS: HTTPS + PostgreSQL + Mosquitto TLS/ACL + signed sessions + C++ runtime movement, latch, reset and heartbeat loss",
  );
} finally {
  clearInterval(timer);
  clearInterval(heartbeat);
  if (engine) engine.stdin.end();
  if (device) await device.endAsync();
  if (appClient) await appClient.endAsync();
  try {
    await request("DELETE", `/robots/${id}/session`);
  } catch {}
  try {
    await broker.revoke(username);
  } catch {}
  await broker.close();
  await db.end();
}
