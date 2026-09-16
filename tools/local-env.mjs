import { readFileSync } from "node:fs";
import { resolve } from "node:path";
export function localEnvironment() {
  const values = Object.fromEntries(
    readFileSync(new URL("../deployment/.env", import.meta.url), "utf8")
      .trim()
      .split("\n")
      .map((line) => {
        const i = line.indexOf("=");
        return [line.slice(0, i), line.slice(i + 1)];
      }),
  );
  const root = resolve(new URL("..", import.meta.url).pathname);
  return {
    ...process.env,
    ...values,
    DATABASE_URL: `postgres://airobot:${values.POSTGRES_PASSWORD}@127.0.0.1:55432/airobot`,
    MQTT_URL: "mqtts://localhost:18883",
    MQTT_CA: root + "/deployment/private/ca.crt",
    MQTT_ADMIN_USER: "admin",
    SIGNING_KEY: root + "/deployment/private/signing.pem",
    PUBLIC_KEY: root + "/deployment/private/signing.pub",
  };
}
