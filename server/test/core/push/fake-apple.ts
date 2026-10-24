import type { Fetch } from "../../../src/core/push/apns-client";
import type { ApnsSettings } from "../../../src/core/push/apns-settings";

/** A request that the server sent to Apple, as the fake received it. */
export interface AppleRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string | undefined;
}

export type AppleReply = { status: number; reason?: string; channelId?: string } | "no-answer";

/**
 * Apple's push service, faked: it records each request and answers as the test says (by default: a new channel id, and each start taken).
 * No test calls Apple for real.
 */
export class FakeApple {
  readonly requests: AppleRequest[] = [];
  private channelCount = 0;
  private reply: (request: AppleRequest) => AppleReply = (request) =>
    request.method === "POST" && request.url.endsWith("/channels")
      ? { status: 201, channelId: `channel-${String((this.channelCount += 1))}` }
      : { status: 200 };

  answerWith(reply: (request: AppleRequest, defaultReply: AppleReply) => AppleReply): void {
    const defaultReply = this.reply;
    this.reply = (request) => reply(request, defaultReply(request));
  }

  readonly fetch: Fetch = (url, init) => {
    const request: AppleRequest = {
      method: init.method ?? "GET",
      url,
      headers: Object.fromEntries(Object.entries((init.headers ?? {}) as Record<string, string>).map(([name, value]) => [name.toLowerCase(), value])),
      body: typeof init.body === "string" ? init.body : undefined,
    };
    this.requests.push(request);
    const reply = this.reply(request);
    if (reply === "no-answer") {
      return Promise.reject(new TypeError(`fetch failed: ${url}`));
    }
    const headers: Record<string, string> = reply.channelId === undefined ? {} : { "apns-channel-id": reply.channelId };
    const body = reply.reason === undefined ? null : JSON.stringify({ reason: reply.reason });
    return Promise.resolve(new Response(body, { status: reply.status, headers }));
  };

  get starts(): AppleRequest[] {
    return this.requests.filter((request) => request.url.includes("/3/device/"));
  }
}

type PublicKey = Awaited<ReturnType<typeof crypto.subtle.importKey>>;

/** Settings with test keys made for each run: the private keys never leave the test, and the public ones check the signatures. */
export async function testApnsSettings(environments: ("production" | "sandbox")[] = ["production", "sandbox"]): Promise<{
  settings: ApnsSettings;
  publicKeys: Record<string, PublicKey>;
}> {
  const publicKeys: Record<string, PublicKey> = {};
  const keys = await Promise.all(
    environments.map(async (environment) => {
      const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
      const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
      const base64 = btoa(String.fromCharCode(...pkcs8));
      const keyId = `KEY${environment.toUpperCase()}`;
      publicKeys[keyId] = pair.publicKey;
      return { environment, keyId, key: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n` };
    }),
  );
  return { settings: { teamId: "TEAMID1234", bundleId: "com.example.trains", keys }, publicKeys };
}
