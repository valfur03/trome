import { describe, expect, it } from "vitest";
import { PrimBudget, type CallKind } from "../../../src/core/budget/prim-budget";
import { relaySettings, type RelaySettings } from "../../../src/core/config/relay-settings";
import type { SqlDatabase } from "../../../src/core/storage/sql-database";
import { hour, minute } from "../../../src/core/time/clock";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { peakDayShape } from "./peak-day-shape";

const at = (iso: string) => Date.parse(iso);
const parisMidnight = at("2026-10-01T22:00:00.000Z");
const parisHourStart = (parisHour: number) => parisMidnight + parisHour * hour;

function budget({
  cap = "800",
  database = new NodeSqliteDatabase(),
  settings = {},
}: { cap?: string; database?: SqlDatabase; settings?: Partial<RelaySettings> } = {}): PrimBudget {
  return new PrimBudget(database, { ...relaySettings({ PRIM_DAILY_CAP: cap }), dayShape: peakDayShape, ...settings });
}

function claimAll(prim: PrimBudget, now: number, kind: CallKind = "start"): number {
  let claimed = 0;
  while (prim.claim(now, kind)) {
    claimed += 1;
  }
  return claimed;
}

function claim(prim: PrimBudget, now: number, calls: number): void {
  for (let index = 0; index < calls; index += 1) {
    expect(prim.claim(now, "start")).toBe(true);
  }
}

describe("PrimBudget: the share of each Paris hour", () => {
  it("lets each Paris hour spend its share of the day's cap, by a day shape of 07:00 15%, 08:00 24%, 09:00 8%, 16:00 6%, 17:00 17%, 18:00 18%, 19:00 7%, and 5% for the other hours", () => {
    const prim = budget();

    const spentByTheEndOf = Array.from({ length: 24 }, (_, parisHour) => {
      claimAll(prim, parisHourStart(parisHour) + 30 * minute);
      return prim.used("2026-10-02");
    });

    expect(spentByTheEndOf).toEqual([2, 4, 7, 9, 11, 14, 16, 136, 328, 392, 394, 397, 399, 401, 404, 406, 454, 590, 734, 790, 792, 795, 797, 800]);
  });

  it("gives what an hour does not spend to the next hour", () => {
    const prim = budget();

    expect(claimAll(prim, parisHourStart(8) + 59 * minute)).toBe(328);
    expect(claimAll(prim, parisHourStart(9))).toBe(392 - 328);
  });

  it("lets each Paris hour spend its share of the day's cap of 800 by the server's own day shape, from 4 calls by the end of 00:00 and 68 by the end of 06:00", () => {
    const prim = budget({ settings: { dayShape: relaySettings({ PRIM_DAILY_CAP: "800" }).dayShape } });

    const spentByTheEndOf = Array.from({ length: 24 }, (_, parisHour) => {
      claimAll(prim, parisHourStart(parisHour) + 30 * minute);
      return prim.used("2026-10-02");
    });

    expect(spentByTheEndOf).toEqual([4, 8, 12, 16, 20, 34, 68, 142, 224, 272, 309, 346, 387, 426, 465, 509, 565, 633, 693, 734, 760, 776, 790, 800]);
  });

  it("keeps the Paris hours from 00:00 to 02:00 of the server's own day shape at 5% of the cap or less (40 calls of 800), so that a PRIM day that starts at 00:00 UTC still holds less than 1,000 calls", () => {
    const prim = budget({ settings: { dayShape: relaySettings({ PRIM_DAILY_CAP: "800" }).dayShape } });

    expect(claimAll(prim, parisHourStart(0)) + claimAll(prim, parisHourStart(1))).toBeLessThanOrEqual(40);
  });

  it("gives the staging cap of 60 its first call at 03:00 in Paris, with the server's own day shape", () => {
    const prim = budget({ cap: "60", settings: { dayShape: relaySettings({ PRIM_DAILY_CAP: "60" }).dayShape } });

    expect(claimAll(prim, parisHourStart(2) + 59 * minute)).toBe(0);
    expect(claimAll(prim, parisHourStart(3))).toBe(1);
  });

  it("never passes the day's cap, and starts again at the next Paris day", () => {
    const prim = budget();

    expect(claimAll(prim, parisHourStart(23) + 59 * minute)).toBe(800);
    expect(claimAll(prim, parisHourStart(24))).toBe(2);
  });

  it("keeps its counts in a database that it opens again", () => {
    const database = new NodeSqliteDatabase();
    const now = parisHourStart(8);
    expect(claimAll(budget({ database }), now)).toBe(328);

    const reopened = budget({ database });
    expect(reopened.claim(now, "start")).toBe(false);
    expect(reopened.answerAge(now)).toBe(5 * minute);
  });

  it("counts the calls of the day that it held before it counted by hour as calls of the hours before", () => {
    const database = new NodeSqliteDatabase();
    database.run("CREATE TABLE prim_budget (paris_day TEXT PRIMARY KEY, calls INTEGER NOT NULL) WITHOUT ROWID");
    database.run("INSERT INTO prim_budget (paris_day, calls) VALUES ('2026-10-02', 300)");

    expect(claimAll(budget({ database }), parisHourStart(8))).toBe(28);
  });

  it("forgets the days before a day", () => {
    const prim = budget();
    claimAll(prim, parisHourStart(8));
    claimAll(prim, parisHourStart(32));

    prim.forgetDaysBefore("2026-10-03");

    expect(prim.used("2026-10-02")).toBe(0);
    expect(prim.used("2026-10-03")).toBe(328);
  });

  it("shares the hour 02:00 that comes twice when the clocks go back, and skips the hour 02:00 that never comes when they go forward", () => {
    const autumn = budget();
    expect(claimAll(autumn, at("2026-10-25T00:30:00.000Z"))).toBe(7);
    expect(claimAll(autumn, at("2026-10-25T01:30:00.000Z"))).toBe(0);
    expect(claimAll(autumn, at("2026-10-25T02:30:00.000Z"))).toBe(9 - 7);

    const spring = budget();
    expect(claimAll(spring, at("2027-03-28T00:30:00.000Z"))).toBe(4);
    expect(claimAll(spring, at("2027-03-28T01:30:00.000Z"))).toBe(9 - 4);
  });
});

describe("PrimBudget: the age of the shared answer", () => {
  it("is 60 s while the hour has spent up to 70% of its share, 120 s above 70%, and 300 s above 90% and when the share is gone", () => {
    const prim = budget();
    const now = parisHourStart(8);
    const ages: number[] = [];

    for (let spent = 0; spent <= 328; spent += 1) {
      ages.push(prim.answerAge(now));
      prim.claim(now, "start");
    }

    expect([ages[0], ages[229], ages[230], ages[295], ages[296], ages[328]]).toEqual([
      minute,
      minute,
      2 * minute,
      2 * minute,
      5 * minute,
      5 * minute,
    ]);
  });

  it("measures the spending against the share of the hour with what the hours before did not spend", () => {
    const prim = budget();
    claim(prim, parisHourStart(7), 136 - 50);
    const now = parisHourStart(8);

    claim(prim, now, Math.floor(0.7 * (328 - 86)));
    expect(prim.answerAge(now)).toBe(minute);
    claim(prim, now, 1);
    expect(prim.answerAge(now)).toBe(2 * minute);
  });

  it("takes the steps from the settings", () => {
    const prim = budget({ settings: { freshAge: 30_000, agedAnswers: [{ spentOver: 0.5, age: 90_000 }] } });
    const now = parisHourStart(8);

    claim(prim, now, 164);
    expect(prim.answerAge(now)).toBe(30_000);
    claim(prim, now, 1);
    expect(prim.answerAge(now)).toBe(90_000);
  });
});

describe("PrimBudget: a start before a refresh", () => {
  it("keeps the last 5% of the share of the hour for the stops that start, and gives them the whole share", () => {
    const prim = budget();
    const now = parisHourStart(8) + 10 * minute;

    expect(claimAll(prim, now, "refresh")).toBe(328 - 17);
    expect(claimAll(prim, now, "start")).toBe(17);
    expect(prim.hasNoCallLeft(now)).toBe(true);
  });
});

describe("PrimBudget: the time when it tries again", () => {
  it("is the start of the next Paris hour", () => {
    const prim = budget();
    claimAll(prim, parisHourStart(8) + 20 * minute);

    expect(prim.retryAt(parisHourStart(8) + 20 * minute)).toBe(parisHourStart(9));
  });

  it("is the start of the first next hour that has a call left: the next Paris day when the day's cap is spent", () => {
    const prim = budget();
    claimAll(prim, parisHourStart(23));

    expect(prim.retryAt(parisHourStart(22) + 10 * minute)).toBe(parisHourStart(24));
    expect(prim.retryAt(parisHourStart(23) + 10 * minute)).toBe(parisHourStart(24));
  });

  it("follows the Paris hours in winter too", () => {
    const prim = budget();
    const now = at("2026-12-15T07:30:00.000Z");
    claimAll(prim, now);

    expect(prim.used("2026-12-15")).toBe(328);
    expect(prim.retryAt(now)).toBe(at("2026-12-15T08:00:00.000Z"));
  });
});
