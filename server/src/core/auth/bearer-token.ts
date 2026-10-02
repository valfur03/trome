const prefix = "Bearer ";
const encoder = new TextEncoder();

export function hasBearerToken(headers: Headers, expected: string): boolean {
  const header = headers.get("authorization");
  if (expected.length === 0 || header?.startsWith(prefix) !== true) {
    return false;
  }
  return sameBytes(encoder.encode(header.slice(prefix.length)), encoder.encode(expected));
}

function sameBytes(given: Uint8Array, expected: Uint8Array): boolean {
  let difference = given.length ^ expected.length;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= (given[index] ?? 0) ^ (expected[index] ?? 0);
  }
  return difference === 0;
}
