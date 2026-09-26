export function progressLabel(done: number, total: number): string {
  return `${done} of ${total} ${total === 1 ? 'step' : 'steps'} done`;
}

export function parseTicks(saved: string | null, total: number): boolean[] {
  const ticks: boolean[] = Array.from({ length: total }, () => false);
  let indexes: unknown;
  try {
    indexes = JSON.parse(saved ?? '[]');
  } catch {
    return ticks;
  }
  if (!Array.isArray(indexes)) return ticks;
  for (const index of indexes) {
    if (Number.isInteger(index) && index >= 0 && index < total) ticks[index] = true;
  }
  return ticks;
}

export function serializeTicks(ticks: boolean[]): string {
  return JSON.stringify(ticks.flatMap((ticked, index) => (ticked ? [index] : [])));
}
