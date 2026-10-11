const prefix = "Bearer ";
const encoder = new TextEncoder();

/**
 * Whether the request carries one of the accepted tokens, exactly: same case, no space around it.
 * It compares the given token with every accepted one, so the time of the answer does not say which one matched.
 */
export function hasBearerToken(headers: Headers, accepted: string | readonly string[]): boolean {
  const header = headers.get("authorization");
  if (header?.startsWith(prefix) !== true) {
    return false;
  }
  const given = encoder.encode(header.slice(prefix.length));
  let found = false;
  for (const token of typeof accepted === "string" ? [accepted] : accepted) {
    found = (token.length > 0 && sameBytes(given, encoder.encode(token))) || found;
  }
  return found;
}

function sameBytes(given: Uint8Array, expected: Uint8Array): boolean {
  let difference = given.length ^ expected.length;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= (given[index] ?? 0) ^ (expected[index] ?? 0);
  }
  return difference === 0;
}
