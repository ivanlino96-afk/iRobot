import mqtt from "mqtt";
import { readFileSync } from "node:fs";
import { random } from "./security.js";
export class Broker {
  states = new Map();
  leases = new Map();
  pending = new Map();
  constructor(env) {
    this.publicEndpoint = {
      host: env.MQTT_PUBLIC_HOST,
      port: Number(env.MQTT_PUBLIC_PORT || 8883),
    };
    if (!env.MQTT_URL?.startsWith("mqtts://") || !env.MQTT_CA)
      throw Error("MQTTS and CA required");
    this.client = mqtt.connect(env.MQTT_URL, {
      username: env.MQTT_ADMIN_USER,
      password: env.MQTT_ADMIN_PASSWORD,
      ca: readFileSync(env.MQTT_CA),
      rejectUnauthorized: true,
      clean: true,
    });
    this.client.on("connect", () =>
      this.client.subscribe(
        ["$CONTROL/dynamic-security/v1/response", "airobot/v1/robots/+/state"],
        { qos: 1 },
      ),
    );
    this.client.on("message", (topic, bytes) => {
      try {
        let m = JSON.parse(bytes);
        if (topic.endsWith("/state")) {
          let id = topic.split("/")[3];
          if (m.robotId === id && m.bootId)
            this.states.set(id, { ...m, receivedAt: Date.now() });
        } else
          for (let response of m.responses || []) {
            let p = this.pending.get(response.correlationData);
            if (p) {
              this.pending.delete(response.correlationData);
              response.error
                ? p.reject(Error(response.error))
                : p.resolve(response);
            }
          }
      } catch {}
    });
    this.timer = setInterval(() => this.cleanup(), 1000);
    this.timer.unref();
  }
  command(command) {
    return new Promise((resolve, reject) => {
      const correlationData = random();
      const timer = setTimeout(() => {
        this.pending.delete(correlationData);
        reject(Error("broker-timeout"));
      }, 5000);
      this.pending.set(correlationData, {
        resolve: (x) => {
          clearTimeout(timer);
          resolve(x);
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      });
      this.client.publish(
        "$CONTROL/dynamic-security/v1",
        JSON.stringify({ commands: [{ ...command, correlationData }] }),
        { qos: 1 },
      );
    });
  }
  async grant(username, password, id, expires, device = false) {
    let prefix = "airobot/v1/robots/+/";
    const role = username;
    let acls = [];
    for (let suffix of device
      ? ["state", "availability", "telemetry", "ack"]
      : ["command", "emergency", "config"])
      acls.push({
        acltype: "publishClientSend",
        topic: prefix + suffix,
        allow: true,
      });
    for (let suffix of device
      ? ["command", "emergency", "config"]
      : ["state", "availability", "telemetry", "ack"]) {
      acls.push({
        acltype: "subscribePattern",
        topic: prefix + suffix,
        allow: true,
      });
      acls.push({
        acltype: "publishClientReceive",
        topic: prefix + suffix,
        allow: true,
      });
    }
    await this.command({ command: "createRole", rolename: role, acls });
    try {
      await this.command({
        command: "createClient",
        username,
        password,
        roles: [{ rolename: role }],
      });
    } catch (e) {
      await this.command({ command: "deleteRole", rolename: role });
      throw e;
    }
    if (!device) this.leases.set(username, expires);
  }
  async extend(user, expires) {
    this.leases.set(user, expires);
  }
  async revoke(user) {
    await this.command({ command: "deleteClient", username: user });
    await this.command({ command: "deleteRole", rolename: user });
    this.leases.delete(user);
  }
  async cleanup() {
    for (let [user, expires] of this.leases)
      if (expires <= Date.now())
        try {
          await this.revoke(user);
        } catch {
          /* retry without granting renewal */
        }
  }
  async close() {
    clearInterval(this.timer);
    await this.client.endAsync();
  }
}
