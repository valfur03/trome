import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { RelayAnswer } from "../../../src/core/relay/relay";
import { contentOfStation } from "../../../src/core/live-activity/content-of-station";
import { StationCatalog } from "../../../src/core/live-activity/station-catalog";
import { encodeContent, staleDate, swiftDate } from "../../../src/core/live-activity/station-content";
import { primFixture } from "../relay/prim-fixtures";

/**
 * The content that the server sends in a start must be the content that the app builds from the same answers.
 * The app's test `LiveActivityContentContractTests` writes `contracts/live-activity/contents/` from the cases of `contracts/live-activity/cases/`; this test builds each case on the server and compares.
 */
const folder = fileURLToPath(new URL("../../../../contracts/live-activity/", import.meta.url));

interface ContractCase {
  station: string;
  now: string;
  answers: Record<string, { prim?: string; answeredAt?: string; out?: "budget" | "prim-limit" | "prim-failure"; retryAt?: string }>;
}

const caseNames = readdirSync(`${folder}cases/`)
  .filter((name) => name.endsWith(".json"))
  .map((name) => name.slice(0, -".json".length))
  .sort();

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8"));
}

function relayAnswer(contractCase: ContractCase, stopRef: string): RelayAnswer {
  const answer = contractCase.answers[stopRef];
  if (answer === undefined) {
    throw new Error(`no answer for ${stopRef}`);
  }
  if (answer.out !== undefined) {
    return { kind: "out", reason: answer.out, retryAt: Date.parse(answer.retryAt ?? "") };
  }
  return { kind: "times", body: primFixture(`${answer.prim ?? ""}.json`), primAnsweredAt: Date.parse(answer.answeredAt ?? "") };
}

/** Swift writes a date as a double, with fractions of a second that JavaScript rounds a little differently. */
function expectSameContent(built: unknown, recorded: unknown, path = "content"): void {
  if (typeof recorded === "number" && typeof built === "number") {
    expect(built, path).toBeCloseTo(recorded, 5);
    return;
  }
  if (Array.isArray(recorded) && Array.isArray(built)) {
    expect(built.length, `${path}.length`).toBe(recorded.length);
    recorded.forEach((item, index) => {
      expectSameContent(built[index], item, `${path}[${String(index)}]`);
    });
    return;
  }
  if (recorded !== null && typeof recorded === "object" && built !== null && typeof built === "object") {
    expect(Object.keys(built).sort(), `${path} keys`).toEqual(Object.keys(recorded).sort());
    for (const [key, value] of Object.entries(recorded)) {
      expectSameContent((built as Record<string, unknown>)[key], value, `${path}.${key}`);
    }
    return;
  }
  expect(built, path).toEqual(recorded);
}

describe("the content of a Live Activity", () => {
  const catalog = StationCatalog.bundled();

  it.each(caseNames)("is the content of the app for the case %s", async (name) => {
    const contractCase = readJson(`${folder}cases/${name}.json`) as ContractCase;
    const station = catalog.station(contractCase.station);
    expect(station).toBeDefined();
    if (station === undefined) {
      return;
    }
    const asked: string[] = [];
    const content = await contentOfStation(
      station,
      catalog,
      (stopRef) => {
        asked.push(stopRef);
        return Promise.resolve(relayAnswer(contractCase, stopRef));
      },
      () => Date.parse(contractCase.now),
    );
    expectSameContent(encodeContent(content), readJson(`${folder}contents/${name}.json`));
    expect(asked.sort()).toEqual(Object.keys(contractCase.answers).sort());
  });

  it("goes stale at the soonest train", async () => {
    const contractCase = readJson(`${folder}cases/abbesses.json`) as ContractCase;
    const station = catalog.station(contractCase.station);
    if (station === undefined) {
      throw new Error("no Abbesses");
    }
    const content = await contentOfStation(station, catalog, (stopRef) => Promise.resolve(relayAnswer(contractCase, stopRef)), () =>
      Date.parse(contractCase.now),
    );
    const recorded = readJson(`${folder}contents/abbesses.json`) as { trains: { lines: { _0: { soonestTrain: { time: number } } } } };
    const stale = staleDate(content);
    expect(stale).toBeDefined();
    expect(swiftDate(stale ?? 0)).toBeCloseTo(recorded.trains.lines._0.soonestTrain.time, 5);
  });
});
