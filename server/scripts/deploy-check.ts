import { readFileSync } from "node:fs";

// node scripts/deploy-check.ts <wrangler output file>
// After a deploy of the GitHub workflow, checks that the new Worker answers: /health, then one request for the trains of
// one stop with the app token of APP_TOKEN_FOR_CHECK, which costs at most one PRIM call.
// The repo is public, so the log of a run is public: this prints the address and the HTTP status, never the token,
// and never the answer of the server.

const stop = "STIF:StopArea:SP:42155:";
const healthTries = 6;
const waitMilliseconds = Number(process.env.DEPLOY_CHECK_WAIT_MS ?? 5000);

function fail(message: string): never {
  console.error(`::error::${message}`);
  process.exit(1);
}

function workerAddress(outputPath: string): string {
  let text: string;
  try {
    text = readFileSync(outputPath, "utf8");
  } catch {
    fail(`The check found no output of wrangler deploy at ${outputPath}, so it cannot know the address of the Worker.`);
  }
  const targets = text
    .split("\n")
    .filter((line) => line.trim() !== "")
    .flatMap((line): unknown[] => {
      try {
        const entry: unknown = JSON.parse(line);
        return typeof entry === "object" && entry !== null && "type" in entry && entry.type === "deploy" && "targets" in entry && Array.isArray(entry.targets)
          ? entry.targets
          : [];
      } catch {
        return [];
      }
    })
    .filter((target): target is string => typeof target === "string" && /^https:\/\/[^/]+\.workers\.dev\/?$/.test(target));
  const address = targets.at(-1);
  if (address === undefined) {
    fail("The output of wrangler deploy names no workers.dev address, so the check cannot reach the Worker.");
  }
  return address.replace(/\/$/, "");
}

async function get(url: string, headers: Record<string, string> = {}): Promise<{ status: number; body: unknown } | { error: string }> {
  try {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(30_000) });
    const text = await response.text();
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      body = undefined;
    }
    return { status: response.status, body };
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

function field(body: unknown, name: string): string | undefined {
  if (typeof body === "object" && body !== null && name in body) {
    const value: unknown = (body as Record<string, unknown>)[name];
    return typeof value === "string" ? value : undefined;
  }
  return undefined;
}

function describe(answer: { status: number; body: unknown } | { error: string }): string {
  if ("error" in answer) {
    return `no answer (${answer.error})`;
  }
  const detail = [field(answer.body, "status"), field(answer.body, "reason") ?? field(answer.body, "error")].filter((part) => part !== undefined).join(" ");
  return `HTTP ${String(answer.status)}${detail === "" ? "" : ` ${detail}`}`;
}

const [outputPath] = process.argv.slice(2);
if (outputPath === undefined) {
  fail("Usage: node scripts/deploy-check.ts <wrangler output file>");
}
const token = process.env.APP_TOKEN_FOR_CHECK ?? "";
if (token === "") {
  fail("The check has no app token (APP_TOKEN_FOR_CHECK): the GitHub environment of this deploy needs its app token secret (server/guide/deploy.md).");
}
const address = workerAddress(outputPath);
// The test of this script points the requests at a fake Worker on this computer; a run never sets it.
const base = process.env.DEPLOY_CHECK_ADDRESS_FOR_TEST ?? address;

let health: Awaited<ReturnType<typeof get>> = { error: "not asked" };
for (let attempt = 1; attempt <= healthTries; attempt += 1) {
  health = await get(`${base}/health`);
  if (!("error" in health) && health.status === 200 && field(health.body, "status") === "ok") {
    break;
  }
  if (attempt < healthTries) {
    await new Promise((resolve) => setTimeout(resolve, waitMilliseconds));
  }
}
if ("error" in health || health.status !== 200 || field(health.body, "status") !== "ok") {
  fail(`Check 1 of 2 failed: ${address}/health gave ${describe(health)} after ${String(healthTries)} tries, not HTTP 200 {"status":"ok"}.`);
}
console.log(`Check 1 of 2 passed: ${address}/health answers {"status":"ok"}.`);

const departures = await get(`${base}/v1/stops/${stop}/departures`, { authorization: `Bearer ${token}` });
if ("error" in departures || departures.status !== 200 || departures.body === undefined) {
  fail(`Check 2 of 2 failed: the trains of one stop, with the app token, gave ${describe(departures)}, not HTTP 200 with the answer of PRIM.`);
}
console.log("Check 2 of 2 passed: the Worker accepts the app token and gives the trains of one stop.");
