import { describe, expect, it } from "vitest";
import { metricsText } from "../../../src/core/metrics/prometheus-metrics";
import { day, hour } from "../../../src/core/time/clock";
import { nextParisDayStart } from "../../../src/core/time/paris-time";
import { UsageCounts, flushDelay } from "../../../src/core/usage/usage-counts";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { parseMetrics } from "./parse-metrics";

interface Sample {
  t: number;
  v: number;
}

// `increase()` of Prometheus 2.55 (promql/functions.go, extrapolatedRate): the range holds both its ends,
// a value lower than the one before is a counter reset, and the result is extrapolated to the ends of the range.
function prometheusIncrease(samples: Sample[], rangeStart: number, rangeEnd: number): number {
  const inRange = samples.filter(({ t }) => t >= rangeStart && t <= rangeEnd);
  const first = inRange[0];
  const last = inRange.at(-1);
  if (!first || !last || inRange.length < 2) {
    return Number.NaN;
  }
  let result = last.v - first.v;
  for (let index = 1; index < inRange.length; index += 1) {
    const previous = inRange[index - 1]?.v ?? 0;
    if ((inRange[index]?.v ?? 0) < previous) {
      result += previous;
    }
  }
  const sampledInterval = (last.t - first.t) / 1000;
  const averageBetween = sampledInterval / (inRange.length - 1);
  let durationToStart = (first.t - rangeStart) / 1000;
  let durationToEnd = (rangeEnd - last.t) / 1000;
  if (durationToStart >= averageBetween * 1.1) {
    durationToStart = averageBetween / 2;
  }
  if (result > 0 && first.v >= 0) {
    durationToStart = Math.min(durationToStart, sampledInterval * (first.v / result));
  }
  if (durationToEnd >= averageBetween * 1.1) {
    durationToEnd = averageBetween / 2;
  }
  return result * ((sampledInterval + durationToStart + durationToEnd) / sampledInterval);
}

describe("what Prometheus reads from /metrics", () => {
  it("gives each Paris day of make server-counts, across a purge, a midnight, a restart and a change of the clock", () => {
    const database = new NodeSqliteDatabase();
    let flushAt = Number.POSITIVE_INFINITY;
    let usage = new UsageCounts(database, (at) => (flushAt = Math.min(flushAt, at)));

    // The last Sunday of October: Paris goes back one hour, so that day has 25 hours.
    const dayStart = nextParisDayStart(Date.parse("2026-10-24T12:00:00.000Z"));
    const dayEnd = nextParisDayStart(dayStart + hour);
    expect(dayEnd - dayStart).toBe(25 * hour);

    // Hours of 31 days ago, which the server forgets during the day.
    for (let at = dayStart - 31 * day; at < dayStart - 29 * day; at += 10 * 60_000) {
      usage.countPrimCall(at);
    }

    const samples: Sample[] = [];
    const previousDay: Sample[] = [];
    const callTimes: number[] = [];
    let lastScrape: number | undefined;
    const start = dayStart - 12 * hour;
    const end = dayEnd + 2 * hour;
    for (let at = start; at <= end; at += 1000) {
      if (at >= flushAt) {
        flushAt = Number.POSITIVE_INFINITY;
        usage.flushWhenDue();
      }
      // A rider's app call about every 7 seconds, more in the day; a restart loses the counts still in memory.
      if (at % 7000 === 0 || at % 3000 === 0) {
        usage.count("appCalls", at);
        callTimes.push(at);
      }
      if (at === dayStart + 9 * hour + 10_000) {
        usage = new UsageCounts(database, (next) => (flushAt = Math.min(flushAt, next)));
        flushAt = Number.POSITIVE_INFINITY;
      }
      if (at % (6 * hour) === 0) {
        usage.forgetOldCounts(at);
      }
      if ((at - start) % 60_000 === 0) {
        const metrics = parseMetrics(metricsText({ ...usage.metricsTotals(at), dailyCap: 800, failuresToday: [] }));
        const value = metrics.get("trome_app_calls_total") ?? Number.NaN;
        const previous = samples.at(-1)?.v;
        if (previous !== undefined && lastScrape !== undefined) {
          // No jump: what Prometheus adds for one scrape is never more than the calls since the scrape before,
          // and those that were not written yet at that scrape.
          const since = lastScrape - 2 * flushDelay;
          expect(value < previous ? value : value - previous).toBeLessThanOrEqual(callTimes.filter((t) => t > since).length);
        }
        samples.push({ t: at, v: value });
        previousDay.push({ t: at, v: metrics.get("trome_app_calls_previous_day") ?? Number.NaN });
        callTimes.splice(0, callTimes.findIndex((t) => t > at - 3 * flushDelay) >>> 0);
        lastScrape = at;
      }
    }

    usage.flushWhenDue();
    const dayOfServerCounts = usage.report().days.find(({ day: shown }) => shown === "2026-10-25");
    const total = dayOfServerCounts?.appCalls ?? 0;
    expect(total).toBeGreaterThan(20_000);

    // increase() over the day misses at most the calls of the last minute before midnight, and of the 30 s that are not written yet.
    const increase = prometheusIncrease(samples, dayStart, dayEnd);
    expect(Math.abs(increase - total)).toBeLessThanOrEqual(2 * 60);

    // The gauge of the previous day gives that day exactly, from the first minute after midnight to the next midnight.
    const readNextDay = previousDay.filter(({ t }) => t >= dayEnd + flushDelay && t < dayEnd + 2 * hour);
    expect(readNextDay.length).toBeGreaterThan(100);
    expect(new Set(readNextDay.map(({ v }) => v))).toEqual(new Set([total]));
  });
});
