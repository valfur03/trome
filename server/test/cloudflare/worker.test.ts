import { env, exports } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { secretNames } from "../../src/core/config/secrets";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("the Worker", () => {
  it("answers at the health address with no key", async () => {
    const response = await exports.default.fetch("https://server.test/health");

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("never prints a secret in its log lines", async () => {
    const secrets = secretNames.map((name) => env[name]);
    expect(secrets.every((secret) => secret.length > 0)).toBe(true);
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...parts: unknown[]) => {
      lines.push(parts.map(String).join(" "));
    });

    for (const secret of secrets) {
      await exports.default.fetch(`https://server.test/${secret}?key=${secret}`, {
        headers: { authorization: `Bearer ${secret}` },
      });
    }

    expect(lines).toHaveLength(secrets.length);
    for (const line of lines) {
      for (const secret of secrets) {
        expect(line).not.toContain(secret);
      }
    }
  });
});
