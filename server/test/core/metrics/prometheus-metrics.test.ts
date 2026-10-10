import { describe, expect, it } from "vitest";
import { allowedLabels, metricsText, type MetricsSnapshot } from "../../../src/core/metrics/prometheus-metrics";
import { hour } from "../../../src/core/time/clock";
import { UsageCounts } from "../../../src/core/usage/usage-counts";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { parseMetrics } from "./parse-metrics";

const zero = { appCalls: 0, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0 };
const snapshot: MetricsSnapshot = {
  today: { appCalls: 12, cacheHits: 7, heldAnswers: 1, outAnswers: 2, primCalls: 5, errors: 3 },
  previousDay: { ...zero, appCalls: 40 },
  dailyCap: 800,
  failuresToday: [
    { kind: "prim-timeout", status: null, count: 1 },
    { kind: "prim-http-error", status: 500, count: 2 },
  ],
};

// The rules of the text format 0.0.4 (prometheus.io/docs/instrumenting/exposition_formats/), which Prometheus 2.55 reads.
const metricName = /^[a-zA-Z_:][a-zA-Z0-9_:]*$/;
const sampleLine = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{((?:[a-zA-Z_][a-zA-Z0-9_]*="(?:[^"\\\n]|\\["\\n])*",?)*)\})? (-?\d+(?:\.\d+)?|NaN|[+-]Inf)$/;

describe("metricsText", () => {
  it("follows the text format: a help and a type line before the samples of each metric, one name each, and a last newline", () => {
    const text = metricsText(snapshot);
    expect(text.endsWith("\n")).toBe(true);
    const typed = new Map<string, string>();
    const helped = new Set<string>();
    for (const line of text.slice(0, -1).split("\n")) {
      const help = /^# HELP (\S+) \S.*$/.exec(line);
      const type = /^# TYPE (\S+) (counter|gauge)$/.exec(line);
      if (help?.[1]) {
        expect(helped.has(help[1])).toBe(false);
        helped.add(help[1]);
      } else if (type?.[1] && type[2]) {
        expect(typed.has(type[1])).toBe(false);
        typed.set(type[1], type[2]);
      } else {
        const sample = sampleLine.exec(line);
        expect(sample, line).not.toBeNull();
        const name = sample?.[1] ?? "";
        expect(name).toMatch(metricName);
        expect(typed.has(name) && helped.has(name), name).toBe(true);
      }
    }
    for (const [name, type] of typed) {
      expect(name.startsWith("trome_"), name).toBe(true);
      expect(name.endsWith("_total"), name).toBe(type === "counter");
    }
  });

  it("shows only labels of the short allowed list, with values that cannot name a rider", () => {
    const usage = new UsageCounts(new NodeSqliteDatabase(), () => undefined);
    const now = Date.parse("2026-10-02T08:30:00.000Z");
    for (const status of [429, 500, 502, null]) {
      usage.recordError({ at: now - hour, kind: status === 429 ? "prim-limit" : "prim-http-error", status });
    }
    // 23:59 in Paris, the day before.
    usage.recordError({ at: Date.parse("2026-10-01T21:59:00.000Z"), kind: "prim-timeout", status: null });
    usage.recordError({ at: Date.parse("2026-10-01T22:00:00.000Z"), kind: "prim-limit", status: 429 });
    const text = metricsText({ ...usage.metricsTotals(now), dailyCap: 800 });

    const labelNames = new Set<string>();
    for (const line of text.split("\n").filter((line) => line.includes("{"))) {
      for (const [, name, value] of line.matchAll(/([a-zA-Z_][a-zA-Z0-9_]*)="([^"]*)"/g)) {
        labelNames.add(name ?? "");
        expect(name === "status" ? /^(\d{3}|none)$/.test(value ?? "") : /^prim-[a-z-]+$/.test(value ?? ""), line).toBe(true);
      }
    }
    expect([...labelNames].every((name) => (allowedLabels as readonly string[]).includes(name))).toBe(true);
    expect(allowedLabels).toEqual(["kind", "status"]);

    const values = parseMetrics(text);
    expect(values.get('trome_prim_call_failures_total{kind="prim-http-error",status="500"}')).toBe(1);
    expect(values.get('trome_prim_call_failures_total{kind="prim-http-error",status="none"}')).toBe(1);
    expect(values.get('trome_prim_call_failures_total{kind="prim-limit",status="429"}')).toBe(2);
    // The timeout of the day before is not a failure of today.
    expect([...values.keys()].some((key) => key.includes("prim-timeout"))).toBe(false);
    expect(values.get("trome_errors_total")).toBe(5);
  });

  it("gives every total, today and on the previous day, and the cap", () => {
    const values = parseMetrics(metricsText(snapshot));

    expect(values.get("trome_app_calls_total")).toBe(12);
    expect(values.get("trome_cache_hits_total")).toBe(7);
    expect(values.get("trome_held_answers_total")).toBe(1);
    expect(values.get("trome_out_answers_total")).toBe(2);
    expect(values.get("trome_prim_calls_total")).toBe(5);
    expect(values.get("trome_errors_total")).toBe(3);
    expect(values.get("trome_app_calls_previous_day")).toBe(40);
    expect(values.get("trome_out_answers_previous_day")).toBe(0);
    expect(values.get("trome_prim_daily_cap")).toBe(800);
  });
});
