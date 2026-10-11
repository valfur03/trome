import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import ts from "typescript";

// Every installed build calls the production Worker at <name>.<account subdomain>.workers.dev, written in the build for good.
// So the name and the workers.dev switch stay as they are while the table of builds of the release guide has a build in the field.
// Every build of that table holds this address: a second address would add a column to the table and a case to this check.
const productionName = "trome-server";
const tableHeading = "## The builds that riders may hold";

const configPath = process.argv[2] ?? fileURLToPath(new URL("../wrangler.jsonc", import.meta.url));
const guidePath =
  process.argv[3] ??
  fileURLToPath(new URL("../../docs/src/content/docs/en/maintain/release-on-the-app-store.mdx", import.meta.url));

function cells(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

// The builds whose status is not "Retired on ...", or undefined when the guide has no table of builds that this check can read.
function buildsInTheField(guide: string): string[] | undefined {
  const lines = guide.split("\n");
  const start = lines.indexOf(tableHeading);
  if (start < 0) {
    return undefined;
  }
  const next = lines.findIndex((line, index) => index > start && line.startsWith("## "));
  const section = lines.slice(start + 1, next < 0 ? undefined : next);
  const header = section.findIndex((line) => line.trim().startsWith("|"));
  if (header < 0) {
    return undefined;
  }
  const status = cells(section[header] ?? "").indexOf("Status");
  const body = section.slice(header + 2);
  const end = body.findIndex((line) => !line.trim().startsWith("|"));
  const rows = (end < 0 ? body : body.slice(0, end)).map(cells);
  if (status < 0 || rows.length === 0) {
    return undefined;
  }
  return rows
    .filter((row) => !(row[status] ?? "").replace(/\*/g, "").startsWith("Retired on "))
    .map((row) => row[0] ?? "");
}

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

let guide = "";
try {
  guide = readFileSync(guidePath, "utf8");
} catch {
  // A missing guide proves no retirement: the change fails below.
}
const inTheField = buildsInTheField(guide);
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
