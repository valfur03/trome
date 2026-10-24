import { apnsHosts, type ApnsKey } from "./apns-settings";
import type { ProviderTokens } from "./provider-token";

/**
 * The requests to Apple's push service that a start needs: a start to the token of an iPhone, and the broadcast channel of a station that the started Live Activity listens to.
 * The answer holds only the status and Apple's reason: never the token, which is in the address of the request, so that no caller can log it by mistake.
 */
export type ApnsAnswer = { ok: true; channelId?: string } | { ok: false; status: number; reason: string };

export interface ApnsClient {
  start(key: ApnsKey, token: string, payload: string, expiresAt: number): Promise<ApnsAnswer>;
  createChannel(key: ApnsKey): Promise<ApnsAnswer>;
  deleteChannel(key: ApnsKey, channelId: string): Promise<ApnsAnswer>;
}

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

const timeout = 10_000;
/** The reasons with which Apple refuses the token of the team: the next push makes a new one. */
const providerTokenReasons = new Set(["ExpiredProviderToken", "InvalidProviderToken"]);

export function createApnsClient(dependencies: { fetch: Fetch; tokens: ProviderTokens; bundleId: string }): ApnsClient {
  const { fetch, tokens, bundleId } = dependencies;

  async function send(key: ApnsKey, url: string, init: RequestInit): Promise<ApnsAnswer> {
    let authorization: string;
    try {
      authorization = `bearer ${await tokens.token(key)}`;
    } catch {
      return { ok: false, status: 0, reason: "unreadable-key" };
    }
    let response: Response;
    try {
      response = await fetch(url, {
        ...init,
        headers: { ...(init.headers as Record<string, string>), authorization },
        signal: AbortSignal.timeout(timeout),
      });
    } catch {
      return { ok: false, status: 0, reason: "no-answer" };
    }
    if (response.ok) {
      await response.body?.cancel();
      const channelId = response.headers.get("apns-channel-id");
      return channelId === null ? { ok: true } : { ok: true, channelId };
    }
    const reason = await reasonOf(response);
    if (providerTokenReasons.has(reason)) {
      tokens.forget(key);
    }
    return { ok: false, status: response.status, reason };
  }

  return {
    start: (key, token, payload, expiresAt) =>
      send(key, `${apnsHosts[key.environment].device}/3/device/${encodeURIComponent(token)}`, {
        method: "POST",
        headers: {
          "apns-push-type": "liveactivity",
          "apns-topic": `${bundleId}.push-type.liveactivity`,
          "apns-priority": "10",
          "apns-expiration": String(Math.floor(expiresAt / 1000)),
          "content-type": "application/json",
        },
        body: payload,
      }),
    createChannel: (key) =>
      send(key, `${apnsHosts[key.environment].channels}/1/apps/${bundleId}/channels`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ "message-storage-policy": 0, "push-type": "LiveActivity" }),
      }),
    deleteChannel: (key, channelId) =>
      send(key, `${apnsHosts[key.environment].channels}/1/apps/${bundleId}/channels`, {
        method: "DELETE",
        headers: { "apns-channel-id": channelId },
      }),
  };
}

async function reasonOf(response: Response): Promise<string> {
  try {
    const body: unknown = await response.json();
    if (typeof body === "object" && body !== null && "reason" in body && typeof body.reason === "string") {
      return body.reason;
    }
  } catch {
    // An answer with no JSON body is told by its status.
  }
  return `status-${String(response.status)}`;
}
