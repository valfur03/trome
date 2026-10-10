import { readFileSync } from "node:fs";
import { countsTable } from "../src/core/usage/counts-table.ts";
import type { CountsReport } from "../src/core/relay/relay.ts";

// Reads the answer of GET /v1/owner/counts on stdin; prints the table, or with "full", the whole report.
const answer = readFileSync(0, "utf8");
let report: CountsReport;
try {
  report = JSON.parse(answer) as CountsReport;
  if (typeof report.today !== "string" || !Array.isArray(report.days)) {
    throw new Error("not a counts report");
  }
} catch {
  process.stderr.write(`The server's answer is not a counts report:\n${answer}\n`);
  process.exit(1);
}

process.stdout.write(process.argv[2] === "full" ? `${JSON.stringify(report, null, 2)}\n` : countsTable(report));
