import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { generateKeyPairSync } from "node:crypto";
import { newDb } from "pg-mem";
import request from "supertest";
import { createApp } from "../src/app.js";
import {
  hash,
  verifyGrant,
  passwordHash,
  passwordValid,
} from "../src/security.js";
const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
});
async function fixture() {
  const memory = newDb(),
    { Pool } = memory.adapters.createPg(),
    db = new Pool();
  await db.query(
    readFileSync(new URL("../src/schema.sql", import.meta.url), "utf8"),
  );
  const broker = {
    states: new Map([
      ["AR-1", { robotId: "AR-1", bootId: "boot", receivedAt: Date.now() }],
    ]),
    publicEndpoint: { host: "mqtt.example.com", port: 8883 },
    grant: async () => {},
    extend: async () => {},
    revoke: async () => {},
  };
  const app = createApp({
    db,
    broker,
    key: privateKey,
    secret: "x".repeat(48),
  });
  const a = await request(app)
    .post("/auth/register")
    .send({ email: "one@example.com", password: "long-password-123" })
    .expect(201);
  const b = await request(app)
    .post("/auth/register")
    .send({ email: "two@example.com", password: "long-password-456" })
    .expect(201);
  await db.query(
    "INSERT INTO robots(id,pairing_hash,pairing_expires) VALUES($1,$2,$3)",
    ["AR-1", hash("one-time"), Date.now() + 60000],
  );
  return { db, app, a: a.body.token, b: b.body.token, broker };
}
const authorized = (app, token, method, path) =>
  request(app)
    [method](path)
    .set("Authorization", "Bearer " + token);
test("password hashing and validation", () => {
  let h = passwordHash("a-long-secret-password");
  assert(passwordValid("a-long-secret-password", h));
  assert(!passwordValid("wrong", h));
  assert.throws(() => passwordHash("short"));
});
test("register stores optional name", async () => {
  let f = await fixture();
  await request(f.app)
    .post("/auth/register")
    .send({
      email: "carla@example.com",
      password: "long-password-789",
      name: "Carla",
    })
    .expect(201);
  let row = (
    await f.db.query("SELECT name FROM users WHERE email=$1", [
      "carla@example.com",
    ])
  ).rows[0];
  assert.equal(row.name, "Carla");
});
test("GET /me returns the authenticated user's email and name", async () => {
  let f = await fixture();
  const carla = await request(f.app)
    .post("/auth/register")
    .send({
      email: "dana@example.com",
      password: "long-password-789",
      name: "Dana",
    })
    .expect(201);
  const me = await authorized(f.app, carla.body.token, "get", "/me").expect(
    200,
  );
  assert.equal(me.body.email, "dana@example.com");
  assert.equal(me.body.name, "Dana");
  const noName = await authorized(f.app, f.a, "get", "/me").expect(200);
  assert.equal(noName.body.email, "one@example.com");
  assert.equal(noName.body.name, null);
});
test("PATCH /me sets and updates the authenticated user's name", async () => {
  let f = await fixture();
  await authorized(f.app, f.a, "patch", "/me")
    .send({ name: "Ivan" })
    .expect(200);
  let me = await authorized(f.app, f.a, "get", "/me").expect(200);
  assert.equal(me.body.name, "Ivan");
  await authorized(f.app, f.a, "patch", "/me")
    .send({ name: "Ivan Lino" })
    .expect(200);
  me = await authorized(f.app, f.a, "get", "/me").expect(200);
  assert.equal(me.body.name, "Ivan Lino");
  await authorized(f.app, f.a, "patch", "/me").send({ name: "" }).expect(400);
  await authorized(f.app, f.a, "patch", "/me")
    .send({ name: "x".repeat(255) })
    .expect(400);
});
test("single-use pairing and shared robot access", async () => {
  let f = await fixture();
  await authorized(f.app, f.a, "post", "/pair")
    .send({ robotId: "AR-1", token: "one-time" })
    .expect(200);
  await authorized(f.app, f.b, "post", "/pair")
    .send({ robotId: "AR-1", token: "one-time" })
    .expect(409);
  await authorized(f.app, f.b, "get", "/robots/AR-1/profile").expect(404);
  const robots = await authorized(f.app, f.b, "get", "/robots").expect(200);
  assert.equal(robots.body[0].id, "AR-1");
  await authorized(f.app, f.b, "get", "/robots/AR-1/state").expect(200);
  f.broker.states.clear();
  await authorized(f.app, f.b, "get", "/robots/AR-1/state").expect(409);

  await f.db.query(
    "INSERT INTO robots(id,pairing_hash,pairing_expires) VALUES($1,$2,$3)",
    ["AR-2", hash("old"), 1],
  );
  await authorized(f.app, f.b, "post", "/pair")
    .send({ robotId: "AR-2", token: "old" })
    .expect(409);
});
test("profile integrity, J2 validation, programs become stale", async () => {
  let f = await fixture();
  await authorized(f.app, f.a, "post", "/pair").send({
    robotId: "AR-1",
    token: "one-time",
  });
  const p = JSON.parse(
    readFileSync(
      new URL("../../contracts/profile.simulation.json", import.meta.url),
    ),
  );
  const invalid = structuredClone(p);
  invalid.servos[2].pcaChannel = 1;
  await authorized(f.app, f.a, "post", "/robots/AR-1/profile")
    .send(invalid)
    .expect(400);
  const response = await authorized(f.app, f.a, "post", "/robots/AR-1/profile")
    .send(p)
    .expect(201);
  assert.equal(hash(response.body.profileJson), response.body.profileHash);
  const body = {
    profileVersion: 1,
    profileHash: response.body.profileHash,
    homeRevision: 1,
    kinematicsVersion: "ik-dls-1",
    orientation: "home",
    confirmed: true,
    steps: [
      { tcp: [0, 0, 0], gripperDegrees: 0, speedPercent: 10, pauseMs: 50 },
    ],
  };
  await authorized(f.app, f.a, "post", "/robots/AR-1/programs")
    .send({ name: "Home", body })
    .expect(201);
  p.version = 2;
  p.homeRevision = 2;
  await authorized(f.app, f.a, "post", "/robots/AR-1/profile")
    .send(p)
    .expect(201);
  const list = await authorized(
    f.app,
    f.a,
    "get",
    "/robots/AR-1/programs",
  ).expect(200);
  assert.equal(list.body[0].needsRevalidation, true);
  await authorized(f.app, f.a, "post", "/robots/AR-1/programs")
    .send({ name: "Stale", body })
    .expect(409);
});
test("signed sessions reject competing clients and renewal after revoke", async () => {
  let f = await fixture();
  await authorized(f.app, f.a, "post", "/pair").send({
    robotId: "AR-1",
    token: "one-time",
  });
  let s = await authorized(f.app, f.a, "post", "/robots/AR-1/session")
    .send({ bootId: "boot", scope: "control" })
    .expect(200);
  let claims = verifyGrant(s.body.authorization, publicKey);
  assert.equal(claims.robotId, "AR-1");
  assert.equal(claims.bootId, "boot");
  await authorized(f.app, f.a, "post", "/robots/AR-1/session")
    .send({ bootId: "boot", scope: "control" })
    .expect(409);
  await authorized(f.app, f.a, "post", "/robots/AR-1/session")
    .send({ bootId: "boot", scope: "control", sessionId: s.body.sessionId })
    .expect(200);
  await authorized(f.app, f.b, "post", "/robots/AR-1/session")
    .send({ bootId: "boot" })
    .expect(409);
  await authorized(f.app, f.a, "delete", "/robots/AR-1/session").expect(200);
  f.broker.states.clear();
  await authorized(f.app, f.a, "post", "/robots/AR-1/session")
    .send({ bootId: "boot", sessionId: s.body.sessionId })
    .expect(409);
});
