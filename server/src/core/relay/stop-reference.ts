const stopReference = /^STIF:(StopArea:SP|StopPoint:Q):\d{1,12}:$/;

export function isStopReference(value: string): boolean {
  return stopReference.test(value);
}
