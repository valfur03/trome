import { describe, expect, it } from "vitest";
import { createLogger, redacted } from "../../../src/core/logging/logger";

const primKey = "prim-key-a1b2c3";
const appToken = "app-token-d4e5f6";

function capture() {
  const lines: string[] = [];
  const logger = createLogger([primKey, appToken], (line) => lines.push(line));
  return { lines, logger };
}

describe("createLogger", () => {
  it("writes one JSON line with the level, the event and the fields", () => {
    const { lines, logger } = capture();

    logger.info("request", { path: "/health", status: 200 });

    expect(lines.map((line) => JSON.parse(line) as unknown)).toEqual([
      { level: "info", event: "request", path: "/health", status: 200 },
    ]);
  });

  it("never prints a secret, in a field, a nested field, a message or an error", () => {
    const { lines, logger } = capture();

    logger.info(`event ${primKey}`, { url: `https://example.test/?key=${primKey}` });
    logger.info("nested", { headers: { authorization: `Bearer ${appToken}` }, list: [appToken] });
    logger.error("failed", { error: new Error(`PRIM refused ${primKey} for ${appToken}`) });

    expect(lines).toHaveLength(3);
    for (const line of lines) {
      expect(line).not.toContain(primKey);
      expect(line).not.toContain(appToken);
      expect(line).toContain(redacted);
    }
  });

  it("never prints a secret in the form that a URL or JSON gives it", () => {
    const token = 'k+/3"q\\=';
    const lines: string[] = [];
    const logger = createLogger([token], (line) => lines.push(line));

    logger.info("request", { path: `/${encodeURIComponent(token)}`, raw: token });

    expect(lines).toHaveLength(1);
    expect(lines[0]).not.toContain(encodeURIComponent(token));
    expect(lines[0]).not.toContain(JSON.stringify(token).slice(1, -1));
    expect(JSON.parse(lines[0] ?? "")).toEqual({
      level: "info",
      event: "request",
      path: `/${redacted}`,
      raw: redacted,
    });
  });

  it("prints an error as its name and message", () => {
    const { lines, logger } = capture();

    logger.error("failed", { error: new TypeError("bad answer") });

    expect(JSON.parse(lines[0] ?? "")).toEqual({ level: "error", event: "failed", error: "TypeError: bad answer" });
  });
});
