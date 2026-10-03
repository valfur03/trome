import type { KnownWarning } from './known-build-warnings.ts';

const colorCode = /\u001b\[[0-9;]*m/g;
const warningMarks = [/\[WARN\]/, /"level":\s*"warn"/, /^npm warn /i, /\(node:\d+\) \w*Warning/];

export function warningLines(output: string): string[] {
  return output
    .replace(colorCode, '')
    .split('\n')
    .filter((line) => warningMarks.some((mark) => mark.test(line)))
    .map((line) => line.trim());
}

export type WarningReport = {
  unknown: string[];
  known: string[];
  stale: KnownWarning[];
};

export function checkWarnings(output: string, knownWarnings: KnownWarning[]): WarningReport {
  const lines = warningLines(output);
  const isKnown = (line: string) => knownWarnings.some(({ text }) => line.includes(text));
  return {
    unknown: lines.filter((line) => !isKnown(line)),
    known: lines.filter(isKnown),
    stale: knownWarnings.filter(({ text }) => !lines.some((line) => line.includes(text))),
  };
}
