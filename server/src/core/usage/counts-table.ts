// Only type imports here: `scripts/counts-table.ts` runs this file with Node's type stripping, which needs file extensions on runtime imports.
import type { CountsReport } from "../relay/relay";

export const daysShown = 14;

const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;
const dayMs = 24 * 60 * 60 * 1000;

interface Line {
  label: string;
  appCalls: number;
  primCalls: number;
  outAnswers: number;
  errors: number;
  busiestHour: string;
}

const numberColumns = [
  { title: "App calls", key: "appCalls" },
  { title: "PRIM calls", key: "primCalls" },
  { title: "Out answers", key: "outAnswers" },
  { title: "Errors", key: "errors" },
] as const;

/**
 * The owner's one-step read of the totals: today so far, then each Paris day of the last 14 days, newest first.
 * A day with no row in the report had no call, so it is a line of zeros.
 * The table starts at the oldest day that the report holds, when that day is in the window, and says so.
 */
export function countsTable(report: Pick<CountsReport, "today" | "days">): string {
  const byDay = new Map(report.days.map((dayCounts) => [dayCounts.day, dayCounts]));
  const oldestDay = report.days.reduce((oldest, { day }) => (day < oldest ? day : oldest), report.today);
  const firstShown = addDays(report.today, -daysShown);
  const start = oldestDay > firstShown ? oldestDay : firstShown;

  const lines: Line[] = [];
  for (let day = report.today; day >= start; day = addDays(day, -1)) {
    const dayCounts = byDay.get(day);
    const busiest = dayCounts?.hours.reduce<{ parisHour: string; appCalls: number } | undefined>(
      (best, hourCounts) =>
        hourCounts.appCalls > (best?.appCalls ?? 0) || (hourCounts.appCalls === best?.appCalls && hourCounts.parisHour < best.parisHour)
          ? hourCounts
          : best,
      undefined,
    );
    lines.push({
      label: day === report.today ? "Today (so far)" : `${weekday(day)} ${day}`,
      appCalls: dayCounts?.appCalls ?? 0,
      primCalls: dayCounts?.primCalls ?? 0,
      outAnswers: dayCounts?.outAnswers ?? 0,
      errors: dayCounts?.errors ?? 0,
      busiestHour: busiest ? `${busiest.parisHour} (${calls(busiest.appCalls)})` : "-",
    });
  }

  const labelWidth = Math.max("Paris day".length, ...lines.map(({ label }) => label.length));
  const row = (label: string, numbers: string[], busiestHour: string): string =>
    [label.padEnd(labelWidth), ...numbers.map((value, index) => value.padStart(numberColumns[index]?.title.length ?? 0)), busiestHour].join("  ");

  const output = [
    row(
      "Paris day",
      numberColumns.map(({ title }) => title),
      "Busiest hour",
    ),
    ...lines.map((line) =>
      row(
        line.label,
        numberColumns.map(({ key }) => String(line[key])),
        line.busiestHour,
      ),
    ),
  ];
  if (start > firstShown) {
    output.push(`No total before ${weekday(start)} ${start}, so the table starts there.`);
  }
  return `${output.join("\n")}\n`;
}

function calls(count: number): string {
  return count === 1 ? "1 call" : `${String(count)} calls`;
}

function dateOf(day: string): Date {
  const [year = 0, month = 1, date = 1] = day.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, date));
}

function addDays(day: string, count: number): string {
  return new Date(dateOf(day).getTime() + count * dayMs).toISOString().slice(0, 10);
}

function weekday(day: string): string {
  return weekdays[dateOf(day).getUTCDay()] ?? "";
}
