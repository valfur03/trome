import { timeLimit } from "../time/time-limit";
import { apnsHosts, type ApnsKey } from "./apns-settings";
import type { ProviderTokens } from "./provider-token";

/**
 * The requests to Apple's push service that a Live Activity needs: a start to the token of an iPhone, the broadcast channel of a station that the started Live Activity listens to, and the updates on that channel.
 * The answer holds only the status and Apple's reason: never the token, which is in the address of the request, so that no caller can log it by mistake.
 */
export type ApnsAnswer = { ok: true; channelId?: string } | { ok: false; status: number; reason: string };

export interface ApnsClient {
  /** `limit` ends the wait early: a start that the app no longer waits for is dropped, before it leaves when it can be. */
  start(key: ApnsKey, token: string, payload: string, expiresAt: number, limit?: AbortSignal): Promise<ApnsAnswer>;
  createChannel(key: ApnsKey): Promise<ApnsAnswer>;
  deleteChannel(key: ApnsKey, channelId: string): Promise<ApnsAnswer>;
  broadcast(key: ApnsKey, channelId: string, payload: string): Promise<ApnsAnswer>;
}

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

const timeout = 10_000;
/**
 * The priority of an update on a channel: Apple sends a priority 10 push at once but counts it against a budget per hour, which an update every minute would spend; a priority 5 push has no such budget, and Apple may group it with others when the iPhone saves power.
 * The waits count down on the iPhone between two updates, so an update a little late shows the right minutes.
 */
const updatePriority = "5";
/** The reasons with which Apple refuses the token of the team: the next push makes a new one. */
const providerTokenReasons = new Set(["ExpiredProviderToken", "InvalidProviderToken"]);

export function createApnsClient(dependencies: { fetch: Fetch; tokens: ProviderTokens; bundleId: string }): ApnsClient {
  const { fetch, tokens, bundleId } = dependencies;

  async function send(key: ApnsKey, url: string, init: RequestInit, limit?: AbortSignal): Promise<ApnsAnswer> {
    let authorization: string;
    try {
      authorization = `bearer ${await tokens.token(key)}`;
    } catch {
      return { ok: false, status: 0, reason: "unreadable-key" };
    }
    if (limit?.aborted === true) {
      return { ok: false, status: 0, reason: "no-answer" };
    }
    const own = timeLimit(timeout);
    const controller = new AbortController();
    const stop = (): void => {
      controller.abort();
    };
    own.signal.addEventListener("abort", stop, { once: true });
    limit?.addEventListener("abort", stop, { once: true });
    try {
      let response: Response;
      try {
        response = await fetch(url, {
          ...init,
          headers: { ...(init.headers as Record<string, string>), authorization },
          signal: controller.signal,
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
    } finally {
      own.end();
      limit?.removeEventListener("abort", stop);
    }
  }

  return {
    start: (key, token, payload, expiresAt, limit) =>
      send(
        key,
        `${apnsHosts[key.environment].device}/3/device/${encodeURIComponent(token)}`,
        {
          method: "POST",
          headers: {
            "apns-push-type": "liveactivity",
            "apns-topic": `${bundleId}.push-type.liveactivity`,
            "apns-priority": "10",
            "apns-expiration": String(Math.floor(expiresAt / 1000)),
            "content-type": "application/json",
          },
          body: payload,
        },
        limit,
      ),
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
    // A channel that stores no message takes only an expiration of 0: an iPhone that is offline at the push misses it, and gets the next one.
    broadcast: (key, channelId, payload) =>
      send(key, `${apnsHosts[key.environment].device}/4/broadcasts/apps/${bundleId}`, {
        method: "POST",
        headers: {
          "apns-channel-id": channelId,
          "apns-push-type": "liveactivity",
          "apns-priority": updatePriority,
          "apns-expiration": "0",
          "content-type": "application/json",
        },
        body: payload,
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
