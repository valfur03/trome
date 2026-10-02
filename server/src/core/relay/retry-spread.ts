const second = 1000;

export function retrySpread(stopRef: string, retryFrom: number, spread: number): number {
  const seconds = Math.floor(spread / second);
  if (seconds <= 0) {
    return 0;
  }
  const key = `${stopRef}@${String(retryFrom)}`;
  let hash = 0x811c9dc5;
  for (let index = 0; index < key.length; index += 1) {
    hash = Math.imul(hash ^ key.charCodeAt(index), 0x01000193) >>> 0;
  }
  return (hash % seconds) * second;
}
