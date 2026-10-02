const second = 1000;

export function retrySpread(stopRef: string, spread: number): number {
  const seconds = Math.floor(spread / second);
  if (seconds <= 0) {
    return 0;
  }
  let hash = 0x811c9dc5;
  for (let index = 0; index < stopRef.length; index += 1) {
    hash = Math.imul(hash ^ stopRef.charCodeAt(index), 0x01000193) >>> 0;
  }
  return (hash % seconds) * second;
}
