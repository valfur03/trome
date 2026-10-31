import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// The waits that the recorded sets of contracts/builds/ promise: a build in the field gives up on an answer after them.
// On top of the server's own time come two parts that a test on Node cannot run:
// - the wake of a server object that slept: 5 ms in the Workers runtime for a first call with its constructor, so 1 s is a wide bound;
// - the phone's own time: its connection to Cloudflare (on a new connection over 4G, about 3 round trips) and the hop to the server object.
export const wakeOfASleepingServerObject = 1_000;
export const marginForThePhone = 2_000;

const buildsFolder = fileURLToPath(new URL("../../../../contracts/builds/", import.meta.url));

export interface RecordedSet {
  app: { waitForOneAnswerSeconds: number };
  liveActivityStart?: { app: { waitForTheAnswerSeconds: number } };
}

/** The shortest wait that `read` finds in the recorded sets, with the folder of its set; undefined when no set holds one. */
export function shortestRecordedWait(read: (set: RecordedSet) => number | undefined): { seconds: number; set: string } | undefined {
  const waits = readdirSync(buildsFolder, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .flatMap((entry) => {
      const seconds = read(JSON.parse(readFileSync(`${buildsFolder}${entry.name}/promises.json`, "utf8")) as RecordedSet);
      return seconds === undefined ? [] : [{ seconds, set: entry.name }];
    });
  return waits.reduce<{ seconds: number; set: string } | undefined>(
    (shortest, wait) => (shortest === undefined || wait.seconds < shortest.seconds ? wait : shortest),
    undefined,
  );
}
