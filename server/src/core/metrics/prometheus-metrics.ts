import type { Tallies, Tally } from "../usage/usage-counts";

/** The totals that `/metrics` shows: only what the server already keeps, with no stop and no identifier. */
export interface MetricsSnapshot {
  /** Each tally since Paris midnight, from the written hours only, so that a value never goes down within a day. */
  today: Tallies;
  /** Each tally of the whole previous Paris day: the same numbers as that day of `make server-counts`. */
  previousDay: Tallies;
  dailyCap: number;
  /** The failed PRIM calls since Paris midnight, by kind and HTTP status (`null` when PRIM gave no status). */
  failuresToday: { kind: string; status: number | null; count: number }[];
}

export const metricsContentType = "text/plain; version=0.0.4; charset=utf-8";

/** The only label names that a metric may have: neither can hold a stop, an IP address, a time or an identifier. */
export const allowedLabels = ["kind", "status"] as const;

const names: Record<Tally, { name: string; help: string }> = {
  appCalls: { name: "app_calls", help: "Requests for times with the right app token" },
  cacheHits: { name: "cache_hits", help: "App calls answered with an answer that the server already held" },
  heldAnswers: { name: "held_answers", help: "App calls answered with a held answer while the server could not ask PRIM" },
  outAnswers: { name: "out_answers", help: "App calls answered 503 out, with no times" },
  primCalls: { name: "prim_calls", help: "Calls of the server to PRIM" },
  errors: { name: "errors", help: "Failed PRIM calls" },
};

const order: Tally[] = ["appCalls", "cacheHits", "heldAnswers", "outAnswers", "primCalls", "errors"];

/**
 * The totals in the Prometheus text format, version 0.0.4.
 * The counters count since Paris midnight, and start again from 0 there: Prometheus reads that as a counter reset, as after a restart, so `increase()` and `rate()` stay right.
 * A counter never counts the hours of the last 30 days, so the server forgetting an old hour moves no number.
 * The `_previous_day` gauges give each whole Paris day exactly, even when a scrape is missed before midnight.
 */
export function metricsText(snapshot: MetricsSnapshot): string {
  const lines: string[] = [];
  for (const tally of order) {
    const { name, help } = names[tally];
    family(lines, `trome_${name}_total`, "counter", `${help}, since 00:00 in Paris.`, [{ value: snapshot.today[tally] }]);
  }
  for (const tally of order) {
    const { name, help } = names[tally];
    family(lines, `trome_${name}_previous_day`, "gauge", `${help}, in the whole previous Paris day.`, [
      { value: snapshot.previousDay[tally] },
    ]);
  }
  family(lines, "trome_prim_daily_cap", "gauge", "Most PRIM calls that the server makes in one Paris day.", [
    { value: snapshot.dailyCap },
  ]);
  family(
    lines,
    "trome_prim_call_failures_total",
    "counter",
    "Failed PRIM calls by kind and HTTP status (none when PRIM gave no status), since 00:00 in Paris.",
    [...snapshot.failuresToday]
      .sort((a, b) => a.kind.localeCompare(b.kind) || String(a.status).localeCompare(String(b.status)))
      .map(({ kind, status, count }) => ({ labels: { kind, status: status === null ? "none" : String(status) }, value: count })),
  );
  return `${lines.join("\n")}\n`;
}

interface Sample {
  labels?: Partial<Record<(typeof allowedLabels)[number], string>>;
  value: number;
}

function family(lines: string[], name: string, type: "counter" | "gauge", help: string, samples: Sample[]): void {
  lines.push(`# HELP ${name} ${help}`, `# TYPE ${name} ${type}`);
  for (const { labels, value } of samples) {
    const pairs = Object.entries(labels ?? {}).map(([label, text]) => `${label}="${escaped(text)}"`);
    lines.push(`${name}${pairs.length > 0 ? `{${pairs.join(",")}}` : ""} ${String(value)}`);
  }
}

function escaped(text: string): string {
  return text.replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("\n", "\\n");
}
