import { describe, expect, it } from "vitest";
import { PrimBudget } from "../../../src/core/budget/prim-budget";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";

describe("PrimBudget", () => {
  it("gives a call while the day is under its cap, and refuses the call after", () => {
    const budget = new PrimBudget(new NodeSqliteDatabase(), 3);

    expect([1, 2, 3, 4, 5].map(() => budget.claim("2026-10-02"))).toEqual([true, true, true, false, false]);
    expect(budget.used("2026-10-02")).toBe(3);
    expect(budget.isSpent("2026-10-02")).toBe(true);
  });

  it("counts each day apart", () => {
    const budget = new PrimBudget(new NodeSqliteDatabase(), 1);

    expect(budget.claim("2026-10-02")).toBe(true);
    expect(budget.claim("2026-10-03")).toBe(true);
    expect(budget.isSpent("2026-10-04")).toBe(false);
  });

  it("keeps the count of a database that it opens again", () => {
    const database = new NodeSqliteDatabase();
    new PrimBudget(database, 2).claim("2026-10-02");

    const reopened = new PrimBudget(database, 2);
    expect(reopened.claim("2026-10-02")).toBe(true);
    expect(reopened.claim("2026-10-02")).toBe(false);
  });

  it("forgets the days before a day", () => {
    const budget = new PrimBudget(new NodeSqliteDatabase(), 5);
    budget.claim("2026-10-01");
    budget.claim("2026-10-02");

    budget.forgetDaysBefore("2026-10-02");

    expect(budget.used("2026-10-01")).toBe(0);
    expect(budget.used("2026-10-02")).toBe(1);
  });
});
