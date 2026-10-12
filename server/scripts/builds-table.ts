import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// The table "The builds that riders may hold" of the release guide: one row per build uploaded to Apple, kept forever.
// A build leaves the field only by a status "Retired on <date>: <reason>" in its row.

export const defaultGuidePath = fileURLToPath(
  new URL("../../docs/src/content/docs/en/maintain/release-on-the-app-store.mdx", import.meta.url),
);
const tableHeading = "## The builds that riders may hold";
const retirement = /^Retired on [^:]+:\s*\S/;

export interface BuildRow {
  build: string;
  status: string;
  retired: boolean;
  retiredWithAReason: boolean;
}

function cells(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

/** The rows of the table, or undefined when the guide has no table of builds that this check can read. */
export function buildRows(guide: string): BuildRow[] | undefined {
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
  return rows.map((row) => {
    const text = (row[status] ?? "").replace(/[*`]/g, "").trim();
    return {
      build: row[0] ?? "",
      status: text,
      retired: text.startsWith("Retired on "),
      retiredWithAReason: retirement.test(text),
    };
  });
}

/** The text of the guide, or an empty text when it is missing: a missing guide proves no retirement. */
export function readGuide(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return "";
  }
}
