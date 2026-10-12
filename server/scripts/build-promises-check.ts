import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { buildRows, readGuide, type BuildRow } from "./builds-table.ts";

// Each build that riders may hold has one recorded set of promises in contracts/builds/<set>/: what it sends to the server
// and how it reads each answer. The server tests judge every set (server/test/cloudflare/build-promises.test.ts).
// This check keeps the sets themselves true: a recorded file stays as git first recorded it, unless the release guide
// retires every build of its set, and every build in the field has exactly one set.
// Why: a build never changes once riders hold it, so a set that a server change could edit to match itself would protect nobody.

const setsFolder = "contracts/builds";
const guideInRepo = "docs/src/content/docs/en/maintain/release-on-the-app-store.mdx";

function git(root: string, args: string[]): string {
  return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

const root = process.argv[2] ?? git(fileURLToPath(new URL(".", import.meta.url)), ["rev-parse", "--show-toplevel"]).trim();
const guidePath = process.argv[3] ?? `${root}/${guideInRepo}`;
const problems: string[] = [];

function buildsOf(promises: string, where: string): string[] {
  try {
    const parsed = JSON.parse(promises) as { builds?: unknown };
    if (Array.isArray(parsed.builds) && parsed.builds.length > 0 && parsed.builds.every((build) => typeof build === "string")) {
      return parsed.builds;
    }
  } catch {
    // Reported below.
  }
  problems.push(`${where} has no list of builds: it needs "builds": ["<version> (<build>)", ...], as in the table of the release guide.`);
  return [];
}

if (git(root, ["rev-parse", "--is-shallow-repository"]).trim() === "true") {
  console.error(`${root} has only part of its git history, so this check cannot see what each set was when it was recorded: fetch the whole history (git fetch --unshallow).`);
  process.exit(1);
}

// The first commit that added each file of a set, in the history of HEAD.
const recordedIn = new Map<string, string>();
let hasHistory = true;
try {
  git(root, ["rev-parse", "--verify", "--quiet", "HEAD"]);
} catch {
  hasHistory = false;
}
let commit = "";
for (const line of !hasHistory ? [] : git(root, ["log", "--reverse", "--no-renames", "--diff-filter=A", "--format=@%H", "--name-only", "--", setsFolder]).split("\n")) {
  if (line.startsWith("@")) {
    commit = line.slice(1);
  } else if (line.split("/").length > 3 && !recordedIn.has(line)) {
    recordedIn.set(line, commit);
  }
}

// The files that differ from their recording, or are gone, by set.
const changedSets = new Map<string, string[]>();
for (const [path, addedIn] of recordedIn) {
  const set = path.split("/")[2] ?? "";
  const now = existsSync(`${root}/${path}`) ? git(root, ["hash-object", "--", path]).trim() : undefined;
  if (now !== git(root, ["rev-parse", `${addedIn}:${path}`]).trim()) {
    changedSets.set(set, [...(changedSets.get(set) ?? []), `${path} ${now === undefined ? "is gone" : "changed"} (recorded in ${addedIn.slice(0, 7)})`]);
  }
}

const rows: BuildRow[] | undefined = buildRows(readGuide(guidePath));
if (rows === undefined) {
  problems.push(`The table "The builds that riders may hold" of ${guidePath} cannot be read, so no build can be shown retired.`);
}
const rowOf = (build: string): BuildRow | undefined => rows?.find((row) => row.build === build);

for (const [set, changes] of changedSets) {
  const promisesPath = `${setsFolder}/${set}/promises.json`;
  const recordedPromises = recordedIn.get(promisesPath);
  const builds = recordedPromises === undefined ? [] : buildsOf(git(root, ["show", `${recordedPromises}:${promisesPath}`]), promisesPath);
  const inTheField = builds.filter((build) => rowOf(build)?.retiredWithAReason !== true);
  if (builds.length > 0 && inTheField.length === 0) {
    continue;
  }
  problems.push(
    `The recorded set of promises ${setsFolder}/${set}/ changed, but its builds ${inTheField.join(", ") || "(none named)"} are not retired in the release guide:\n` +
      changes.map((change) => `  ${change}\n`).join("") +
      "  A recorded set is never edited: riders still hold these builds, and the server must keep each answer as they read it.\n" +
      "  Put the set back (git checkout -- " + `${setsFolder}/${set}` + "), and change the server by adding next to what these builds read.\n" +
      "  A set leaves only when every one of its builds has the status 'Retired on <date>: <reason>' in the table of the release guide.",
  );
}

// The sets of the working tree: each names its builds, each build in the field has exactly one.
const folder = `${root}/${setsFolder}`;
const sets = existsSync(folder) ? readdirSync(folder, { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name) : [];
const setsOfBuild = new Map<string, string[]>();
for (const set of sets) {
  const promisesPath = `${setsFolder}/${set}/promises.json`;
  const promises = existsSync(`${root}/${promisesPath}`) ? readFileSync(`${root}/${promisesPath}`, "utf8") : "";
  for (const build of buildsOf(promises, promisesPath)) {
    setsOfBuild.set(build, [...(setsOfBuild.get(build) ?? []), set]);
    if (rows !== undefined && rowOf(build) === undefined) {
      problems.push(`${promisesPath} names the build ${build}, which the table of the release guide does not list: add its row in the same commit.`);
    }
  }
}
for (const row of rows ?? []) {
  const setsOfThisBuild = setsOfBuild.get(row.build) ?? [];
  if (!row.retired && setsOfThisBuild.length === 0) {
    problems.push(
      `The build ${row.build} is in the field but has no recorded set of promises in ${setsFolder}/: record it in the commit of its row, as the upload step of the release guide says.`,
    );
  }
  if (setsOfThisBuild.length > 1) {
    problems.push(
      `The build ${row.build} has ${String(setsOfThisBuild.length)} recorded sets (${setsOfThisBuild.join(", ")}): a build has one set, which is never swapped for another.`,
    );
  }
}

if (problems.length > 0) {
  console.error(problems.join("\n"));
  process.exit(1);
}
