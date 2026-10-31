import { generateKeyPairSync } from "node:crypto";
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const testSecrets = {
  PRIM_API_KEY: "test-prim-key-0d6f1c",
  APP_TOKEN: "test-app-token-9b42ae",
  OWNER_TOKEN: "test-owner-token-5c71d0",
};

Object.assign(process.env, testSecrets);

/** The push key of Apple, faked with a key made at each run, for the tests of the Live Activities in the Cloudflare runtime: the other tests run with no push key, as a deploy may. */
const pushSecrets = {
  APNS_TEAM_ID: "TEAMID1234",
  APNS_BUNDLE_ID: "com.example.trains",
  APNS_SANDBOX_KEY_ID: "KEYID12345",
  APNS_SANDBOX_KEY: generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
};
const withPushKey = "test/cloudflare/**/*-with-push-key.test.ts";
/** Fails a test in which workerd ran an alarm of the server object on its own, where its error fails nothing. */
const alarmGuard = "test/cloudflare/alarm-guard.ts";

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: "core",
          environment: "node",
          include: ["test/core/**/*.test.ts"],
        },
      },
      {
        plugins: [
          cloudflareTest({
            wrangler: { configPath: "./wrangler.jsonc" },
            miniflare: { bindings: testSecrets },
          }),
        ],
        test: {
          name: "cloudflare",
          setupFiles: [alarmGuard],
          include: ["test/cloudflare/**/*.test.ts"],
          exclude: [withPushKey],
        },
      },
      {
        plugins: [
          cloudflareTest({
            wrangler: { configPath: "./wrangler.jsonc" },
            miniflare: { bindings: { ...testSecrets, ...pushSecrets } },
          }),
        ],
        test: {
          name: "cloudflare-push",
          setupFiles: [alarmGuard],
          include: [withPushKey],
        },
      },
    ],
  },
});
