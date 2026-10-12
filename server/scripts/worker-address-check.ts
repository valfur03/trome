import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import ts from "typescript";
import { buildRows, defaultGuidePath, readGuide } from "./builds-table.ts";

// Every installed build calls the production Worker at <name>.<account subdomain>.workers.dev, written in the build for good.
// So the name and the workers.dev switch stay as they are while the table of builds of the release guide has a build in the field.
// Every build of that table holds this address: a second address would add a column to the table and a case to this check.
const productionName = "trome-server";

const configPath = process.argv[2] ?? fileURLToPath(new URL("../wrangler.jsonc", import.meta.url));
const guidePath = process.argv[3] ?? defaultGuidePath;

const parsed = ts.parseConfigFileTextToJson(configPath, readFileSync(configPath, "utf8"));
const config: unknown = parsed.config;
if (parsed.error || typeof config !== "object" || config === null) {
  console.error(`Cannot read ${configPath}`);
  process.exit(1);
}
const worker = config as Record<string, unknown>;
const problems: string[] = [];
if (worker.name !== productionName) {
  problems.push(`name must stay "${productionName}": the address holds it.`);
}
if (worker.workers_dev !== true) {
  problems.push("workers_dev must stay true: with false, or with no value, the workers.dev address can stop answering.");
}
if (problems.length === 0) {
  process.exit(0);
}

const inTheField = buildRows(readGuide(guidePath))
  ?.filter((row) => !row.retired)
  .map((row) => row.build);
if (inTheField?.length === 0) {
  console.log(`${configPath} changes the address of the production Worker: allowed, since the release guide lists no build in the field.`);
  process.exit(0);
}

const builds = inTheField === undefined ? `the table of builds of ${guidePath} cannot be read` : `builds in the field: ${inTheField.join(", ")}`;
console.error(
  `${configPath} changes the address of the production Worker, and every installed build calls that address (${builds}). ` +
    "Such a build then shows no times, and no message can reach it. " +
    "Add a new address next to the old one; the old one goes only when every build of the release guide is retired. " +
    "See server/guide/deploy.md, section 'Keep the address of the server'.",
);
for (const problem of problems) {
  console.error(`  ${problem}`);
}
process.exit(1);
