import { describe, expect, it } from "vitest";
import { Counters } from "../../../src/core/counting/counters";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";

describe("Counters", () => {
  it("reads 0 for a counter that was never added to", () => {
    expect(new Counters(new NodeSqliteDatabase()).read("prim-calls")).toBe(0);
  });

  it("adds to a counter and gives its new value", () => {
    const counters = new Counters(new NodeSqliteDatabase());

    expect(counters.add("prim-calls")).toBe(1);
    expect(counters.add("prim-calls", 4)).toBe(5);
    expect(counters.read("prim-calls")).toBe(5);
  });

  it("keeps each counter apart", () => {
    const counters = new Counters(new NodeSqliteDatabase());

    counters.add("prim-calls", 2);
    counters.add("app-calls", 7);

    expect(counters.read("prim-calls")).toBe(2);
    expect(counters.read("app-calls")).toBe(7);
  });

  it("keeps the values of a database that it opens again", () => {
    const database = new NodeSqliteDatabase();
    new Counters(database).add("prim-calls", 3);

    expect(new Counters(database).read("prim-calls")).toBe(3);
  });
});
