import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import ts from "typescript";

type Block = Record<string, unknown>;

const configPath = process.argv[2] ?? fileURLToPath(new URL("../wrangler.jsonc", import.meta.url));

function isBlock(value: unknown): value is Block {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function observabilityProblems(place: string, observability: unknown): string[] {
  if (!isBlock(observability) || observability.enabled !== false) {
    return [`${place}observability.enabled must be false: with true, or with no value, Cloudflare turns Workers Logs on.`];
  }
  return Object.entries(observability).flatMap(([name, part]) => {
    if (!isBlock(part)) {
      return [];
    }
    const problems: string[] = [];
    if (part.enabled === true) {
      problems.push(`${place}observability.${name}.enabled must not be true: it keeps each request at Cloudflare.`);
    }
    if (Array.isArray(part.destinations) && part.destinations.length > 0) {
      problems.push(`${place}observability.${name}.destinations must be empty: it sends each request, with its URL, to another service.`);
    }
    return problems;
  });
}

function workerProblems(place: string, worker: Block): string[] {
  const problems = observabilityProblems(place, worker.observability);
  if (worker.logpush === true) {
    problems.push(`${place}logpush must not be true: it sends each request, with its URL, to a log store.`);
  }
  for (const key of ["tail_consumers", "streaming_tail_consumers"]) {
    const consumers = worker[key];
    if (Array.isArray(consumers) && consumers.length > 0) {
      problems.push(`${place}${key} must be empty: a tail Worker gets each request, with its URL.`);
    }
  }
  return problems;
}

const parsed = ts.parseConfigFileTextToJson(configPath, readFileSync(configPath, "utf8"));
if (parsed.error || !isBlock(parsed.config)) {
  console.error(`Cannot read ${configPath}`);
  process.exit(1);
}
const config = parsed.config;
const environments = isBlock(config.env) ? Object.entries(config.env) : [];
const problems = [
  ...workerProblems("", config),
  ...environments.flatMap(([name, worker]) => (isBlock(worker) ? workerProblems(`env.${name}.`, worker) : [])),
];

if (problems.length > 0) {
  console.error(
    `${configPath} would make Cloudflare keep each request, with its URL and so the stop of the rider. ` +
      "The app promises that the server keeps no stop: see server/guide/deploy.md, section 'Find a problem'.",
  );
  for (const problem of problems) {
    console.error(`  ${problem}`);
  }
  process.exit(1);
}
