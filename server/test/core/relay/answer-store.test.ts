import { describe, expect, it } from "vitest";
import { AnswerStore } from "../../../src/core/relay/answer-store";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";

const abbesses = "STIF:StopArea:SP:42155:";

describe("AnswerStore", () => {
  it("keeps the answer of each stop in memory, and in storage a copy with the stop, the body and the time of the PRIM answer only", () => {
    const database = new NodeSqliteDatabase();
    const store = new AnswerStore(database);

    store.keep(abbesses, { body: "{}", primAnsweredAt: 1 });
    store.keep(abbesses, { body: '{"next":true}', primAnsweredAt: 2 });

    expect(store.answer(abbesses)).toEqual({ body: '{"next":true}', primAnsweredAt: 2 });
    expect(database.all("SELECT name FROM sqlite_master WHERE type = 'table'")).toEqual([{ name: "shared_answers" }, { name: "relay_pauses" }]);
    expect(database.all("SELECT * FROM shared_answers")).toEqual([{ stop_ref: abbesses, body: '{"next":true}', prim_answered_at: 2 }]);
  });

  it("reads the copy in storage when its memory is empty, as after a sleep of the server", () => {
    const database = new NodeSqliteDatabase();
    new AnswerStore(database).keep(abbesses, { body: "{}", primAnsweredAt: 1 });

    const afterSleep = new AnswerStore(database);

    expect(afterSleep.stopsHeld()).toEqual([]);
    expect(afterSleep.answer(abbesses)).toEqual({ body: "{}", primAnsweredAt: 1 });
    expect(afterSleep.answer("STIF:StopArea:SP:417675:")).toBeUndefined();
  });

  it("forgets the copies in storage that PRIM gave by a time, and says when the oldest answer and copy were given", () => {
    const database = new NodeSqliteDatabase();
    const store = new AnswerStore(database);
    store.keep(abbesses, { body: "{}", primAnsweredAt: 10 });
    store.keep("STIF:StopArea:SP:417675:", { body: "{}", primAnsweredAt: 11 });
    expect(store.oldestAnswers()).toEqual({ inMemory: 10, copy: 10 });

    store.forgetCopiesGivenBy(10);

    expect(database.all("SELECT stop_ref FROM shared_answers")).toEqual([{ stop_ref: "STIF:StopArea:SP:417675:" }]);
    expect(store.oldestAnswers()).toEqual({ inMemory: 10, copy: 11 });
    store.forgetAnswersGivenBy(11);
    store.forgetCopiesGivenBy(11);
    expect(store.oldestAnswers()).toEqual({ inMemory: undefined, copy: undefined });
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
