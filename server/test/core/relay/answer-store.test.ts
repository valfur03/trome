import { describe, expect, it } from "vitest";
import { AnswerStore } from "../../../src/core/relay/answer-store";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";

const abbesses = "STIF:StopArea:SP:42155:";

describe("AnswerStore", () => {
  it("keeps the answer of each stop in memory, and writes no stop to storage", () => {
    const database = new NodeSqliteDatabase();
    const store = new AnswerStore(database);

    store.keep(abbesses, { body: "{}", primAnsweredAt: 1 });

    expect(store.answer(abbesses)).toEqual({ body: "{}", primAnsweredAt: 1 });
    expect(database.all("SELECT name FROM sqlite_master WHERE type = 'table'")).toEqual([{ name: "relay_pauses" }]);
  });

  it("deletes the answers that an older version stored with their stop", () => {
    const database = new NodeSqliteDatabase();
    database.run("CREATE TABLE answers (stop_ref TEXT PRIMARY KEY, body TEXT NOT NULL, prim_answered_at INTEGER NOT NULL) WITHOUT ROWID");
    database.run("INSERT INTO answers VALUES (?, '{}', 1)", abbesses);

    const store = new AnswerStore(database);

    expect(store.answer(abbesses)).toBeUndefined();
    expect(database.all("SELECT name FROM sqlite_master WHERE name = 'answers'")).toEqual([]);
  });

  it("forgets the answers that PRIM gave by a time", () => {
    const store = new AnswerStore(new NodeSqliteDatabase());
    store.keep(abbesses, { body: "{}", primAnsweredAt: 10 });
    store.keep("STIF:StopArea:SP:417675:", { body: "{}", primAnsweredAt: 11 });

    store.forgetAnswersGivenBy(10);

    expect(store.stopsHeld()).toEqual(["STIF:StopArea:SP:417675:"]);
  });
});
