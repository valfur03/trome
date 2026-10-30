import { describe, expect, it } from "vitest";
import type { DayCounts, HourCounts } from "../../../src/core/usage/usage-counts";
import { countsTable } from "../../../src/core/usage/counts-table";

function hourOf(parisHour: string, appCalls: number): HourCounts {
  return { start: "", parisHour, appCalls, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0, unreadableAnswers: 0, startAnswers: {} };
}

function dayOf(day: string, hours: HourCounts[], extra: Partial<DayCounts> = {}): DayCounts {
  const appCalls = hours.reduce((sum, hour) => sum + hour.appCalls, 0);
  return { day, appCalls, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0, unreadableAnswers: 0, startAnswers: {}, hours, ...extra };
}

function linesOf(table: string): string[] {
  return table.trimEnd().split("\n");
}

describe("the counts table", () => {
  it("shows today so far, then the 14 days before it, newest first, in 80 columns", () => {
    const table = countsTable({
      today: "2026-10-10",
      days: [
        dayOf("2026-10-10", [hourOf("08:00", 3)]),
        dayOf("2026-09-20", [hourOf("08:00", 1)]),
      ],
    });
    const lines = linesOf(table);

    expect(lines).toHaveLength(17);
    expect(lines[0]).toBe("Paris day       App calls  PRIM calls  Out answers  Errors  Busiest hour");
    expect(lines[1]).toBe("Today (so far)          3           0            0       0  08:00 (3 calls)");
    expect(lines[2]?.startsWith("Fri 2026-10-09")).toBe(true);
    expect(lines[15]?.startsWith("Sat 2026-09-26")).toBe(true);
    expect(table).not.toContain("2026-09-25");
    expect(table).not.toContain("No total before");
    expect(lines[16]).toBe("Live Activity starts: none.");
    expect(Math.max(...lines.map((line) => line.length))).toBeLessThanOrEqual(80);
  });

  it("shows a day with no call as a line of zeros", () => {
    const lines = linesOf(
      countsTable({
        today: "2026-10-10",
        days: [dayOf("2026-10-10", [hourOf("09:00", 1)]), dayOf("2026-10-08", [hourOf("18:00", 2)])],
      }),
    );

    expect(lines[2]).toBe("Fri 2026-10-09          0           0            0       0  -");
  });

  it("names the hour with the most app calls, the earliest one on a tie", () => {
    const lines = linesOf(
      countsTable({
        today: "2026-10-10",
        days: [
          dayOf("2026-10-10", [hourOf("19:00", 4), hourOf("18:00", 9), hourOf("08:00", 9), hourOf("07:00", 1)], {
            primCalls: 6,
            outAnswers: 2,
            errors: 1,
          }),
        ],
      }),
    );

    expect(lines[1]).toBe("Today (so far)         23           6            2       1  08:00 (9 calls)");
  });

  it("starts at the oldest day it has when that day is less than 14 days ago, and says so", () => {
    const lines = linesOf(
      countsTable({ today: "2026-10-10", days: [dayOf("2026-10-07", [hourOf("08:00", 1)])] }),
    );

    expect(lines).toEqual([
      "Paris day       App calls  PRIM calls  Out answers  Errors  Busiest hour",
      "Today (so far)          0           0            0       0  -",
      "Fri 2026-10-09          0           0            0       0  -",
      "Thu 2026-10-08          0           0            0       0  -",
      "Wed 2026-10-07          1           0            0       0  08:00 (1 call)",
      "No total before Wed 2026-10-07, so the table starts there.",
      "Live Activity starts: none.",
    ]);
  });

  it("names the days with PRIM answers that the builds cannot read under the table, and where to look", () => {
    const lines = linesOf(
      countsTable({
        today: "2026-10-10",
        days: [
          dayOf("2026-10-10", [hourOf("08:00", 3)], { unreadableAnswers: 4 }),
          dayOf("2026-10-09", [hourOf("08:00", 1)]),
          dayOf("2026-10-08", [hourOf("08:00", 1)], { unreadableAnswers: 1 }),
        ],
      }),
    );

    expect(lines.slice(-3, -1)).toEqual([
      "Unreadable PRIM answers: Today (so far) 4, Thu 2026-10-08 1.",
      "See server/guide/how-it-works.md, section Unreadable PRIM answers.",
    ]);
    expect(lines[0]).toBe("Paris day       App calls  PRIM calls  Out answers  Errors  Busiest hour");
  });

  it("reads the report of a server older than the count of unreadable answers", () => {
    const olderDay: Partial<DayCounts> = dayOf("2026-10-10", [hourOf("08:00", 3)]);
    delete olderDay.unreadableAnswers;
    const table = countsTable({ today: "2026-10-10", days: [olderDay as DayCounts] });

    expect(table).not.toContain("Unreadable");
  });

  it("shows only today when the server has no total yet", () => {
    expect(linesOf(countsTable({ today: "2026-10-10", days: [] }))).toEqual([
      "Paris day       App calls  PRIM calls  Out answers  Errors  Busiest hour",
      "Today (so far)          0           0            0       0  -",
      "No total before Sat 2026-10-10, so the table starts there.",
      "Live Activity starts: none.",
    ]);
  });

  it("gives the answers of the start of a Live Activity of each day that had some, so that a walk tells where its start stopped", () => {
    const lines = linesOf(
      countsTable({
        today: "2026-10-10",
        days: [
          dayOf("2026-10-10", [hourOf("08:00", 3)], { startAnswers: { started: 1, "already-started": 1 } }),
          dayOf("2026-10-09", [hourOf("08:00", 1)]),
          dayOf("2026-10-08", [hourOf("08:00", 1)], { startAnswers: { "refused:BadDeviceToken": 2, "bad-request": 1 } }),
        ],
      }),
    );

    expect(lines.slice(-2)).toEqual([
      "Live Activity starts, Today (so far): already-started 1, started 1.",
      "Live Activity starts, Thu 2026-10-08: bad-request 1, refused:BadDeviceToken 2.",
    ]);
    expect(Math.max(...lines.map((line) => line.length))).toBeLessThanOrEqual(80);
  });

  it("says nothing of the starts when the report comes from a server older than their count", () => {
    const olderDay: Partial<DayCounts> = dayOf("2026-10-10", [hourOf("08:00", 3)]);
    delete olderDay.startAnswers;
    const table = countsTable({ today: "2026-10-10", days: [olderDay as DayCounts] });

    expect(table).not.toContain("Live Activity");
  });
});
