import { describe, expect, it } from "vitest";
import type { DayCounts, HourCounts } from "../../../src/core/usage/usage-counts";
import { countsTable } from "../../../src/core/usage/counts-table";

function hourOf(parisHour: string, appCalls: number): HourCounts {
  return { start: "", parisHour, appCalls, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0 };
}

function dayOf(day: string, hours: HourCounts[], extra: Partial<DayCounts> = {}): DayCounts {
  const appCalls = hours.reduce((sum, hour) => sum + hour.appCalls, 0);
  return { day, appCalls, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0, hours, ...extra };
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

    expect(lines).toHaveLength(16);
    expect(lines[0]).toBe("Paris day       App calls  PRIM calls  Out answers  Errors  Busiest hour");
    expect(lines[1]).toBe("Today (so far)          3           0            0       0  08:00 (3 calls)");
    expect(lines[2]?.startsWith("Fri 2026-10-09")).toBe(true);
    expect(lines[15]?.startsWith("Sat 2026-09-26")).toBe(true);
    expect(table).not.toContain("2026-09-25");
    expect(table).not.toContain("No total before");
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
    ]);
  });

  it("shows only today when the server has no total yet", () => {
    expect(linesOf(countsTable({ today: "2026-10-10", days: [] }))).toEqual([
      "Paris day       App calls  PRIM calls  Out answers  Errors  Busiest hour",
      "Today (so far)          0           0            0       0  -",
      "No total before Sat 2026-10-10, so the table starts there.",
    ]);
  });
});
