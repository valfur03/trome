import type { Clock } from "../time/clock";
import { minute } from "../time/clock";
import type { ApnsKey } from "./apns-settings";

/**
 * The token that proves to Apple that a push comes from the app's team: a JSON Web Token signed with the key of Apple (ES256).
 * Apple refuses a token older than an hour, and one made again more often than every 20 minutes, so each is kept for 30 minutes.
 */
const tokenAge = 30 * minute;

export class ProviderTokens {
  private readonly held = new Map<string, { token: string; madeAt: number }>();

  constructor(
    private readonly teamId: string,
    private readonly clock: Clock,
  ) {}

  async token(key: ApnsKey): Promise<string> {
    const now = this.clock.now();
    const held = this.held.get(key.keyId);
    if (held !== undefined && now - held.madeAt < tokenAge) {
      return held.token;
    }
    const header = base64Url(JSON.stringify({ alg: "ES256", kid: key.keyId }));
    const claims = base64Url(JSON.stringify({ iss: this.teamId, iat: Math.floor(now / 1000) }));
    const signingKey = await crypto.subtle.importKey("pkcs8", keyBytes(key.key), { name: "ECDSA", namedCurve: "P-256" }, false, [
      "sign",
    ]);
    const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signingKey, new TextEncoder().encode(`${header}.${claims}`));
    const token = `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
    this.held.set(key.keyId, { token, madeAt: now });
    return token;
  }

  /** Apple said that the token is old or wrong: the next push makes a new one. */
  forget(key: ApnsKey): void {
    this.held.delete(key.keyId);
  }
}

/** The bytes of the key: a PEM text, with real line breaks or with `\n` as typed in a prompt, or only its base64. */
function keyBytes(key: string): Uint8Array<ArrayBuffer> {
  const base64 = key
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const text = atob(base64);
  const bytes = new Uint8Array(text.length);
  for (let index = 0; index < text.length; index += 1) {
    bytes[index] = text.charCodeAt(index);
  }
  return bytes;
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let text = "";
  for (const byte of bytes) {
    text += String.fromCharCode(byte);
  }
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
