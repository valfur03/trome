import { describe, expect, it } from "vitest";
import { recordedSets } from "./recorded-sets";
import { judgeTheStartPromises } from "./start-promises";

// The start of the Live Activity of each recorded set of contracts/builds/, in the situations that need a push key of Apple
// (start-promises.ts). Why: a build that riders hold never changes, so the server keeps every answer of its set until the
// release guide retires it.

/** The first build that asks the server to start the Live Activity. */
const firstBuildThatStarts = { version: [1, 0, 0], build: 4 };

function startsTheLiveActivity(build: string): boolean {
  const parts = /^([0-9.]+) \(([0-9]+)\)$/.exec(build);
  if (parts === null) {
    return true;
  }
  const version = (parts[1] ?? "").split(".").map(Number);
  for (let index = 0; index < Math.max(version.length, firstBuildThatStarts.version.length); index += 1) {
    const difference = (version[index] ?? 0) - (firstBuildThatStarts.version[index] ?? 0);
    if (difference !== 0) {
      return difference > 0;
    }
  }
  return Number(parts[2]) >= firstBuildThatStarts.build;
}

describe("the recorded sets of promises of contracts/builds/", () => {
  it("hold the start of the Live Activity from build 1.0.0 (4), the first build that asks the server for it", () => {
    expect(["1.0.0 (3)", "0.9 (12)", "1.0.0 (4)", "1.0.1 (1)", "1.1 (2)"].map(startsTheLiveActivity)).toEqual([false, false, true, true, true]);
    const missing = recordedSets()
      .filter(({ set }) => set.liveActivityStart === undefined && set.builds.some(startsTheLiveActivity))
      .map(({ folder }) => `contracts/builds/${folder}/`);
    expect(missing, "these sets have builds that start the Live Activity but no liveActivityStart: record what the build sends and reads, as the release guide says").toEqual([]);
  });
});

judgeTheStartPromises("with a push key");
