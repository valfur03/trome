import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const testSecrets = {
  PRIM_API_KEY: "test-prim-key-0d6f1c",
  APP_TOKEN: "test-app-token-9b42ae",
  OWNER_TOKEN: "test-owner-token-5c71d0",
};

Object.assign(process.env, testSecrets);

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
          include: ["test/cloudflare/**/*.test.ts"],
        },
      },
    ],
  },
});
