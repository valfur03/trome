/** An answer of the start route, as `LiveActivityStarts` gives it, or a request that the route refused as bad. */
export interface StartAnswer {
  result: string;
  reason?: string;
}

/** The results that the counts keep as they are. An unknown station is a bad ask of the app, as a body with no start token is. */
const results = new Map([
  ["started", "started"],
  ["already-started", "already-started"],
  ["not-set-up", "not-set-up"],
  ["bad-request", "bad-request"],
  ["unknown-station", "bad-request"],
]);

/**
 * The reasons of a refusal that the counts keep as they are: the reasons that Apple documents for a push, and the server's own.
 * Any other text counts as "other", so that a count can never hold a token, a station or the text of an error; the log line of the start still gives the reason.
 */
const reasons = new Set([
  // Apple, "Handling error responses from APNs".
  "BadCollapseId",
  "BadDeviceToken",
  "BadExpirationDate",
  "BadMessageId",
  "BadPriority",
  "BadTopic",
  "DeviceTokenNotForTopic",
  "DuplicateHeaders",
  "IdleTimeout",
  "InvalidPushType",
  "MissingDeviceToken",
  "MissingTopic",
  "PayloadEmpty",
  "TopicDisallowed",
  "BadCertificate",
  "BadCertificateEnvironment",
  "ExpiredProviderToken",
  "Forbidden",
  "InvalidProviderToken",
  "MissingProviderToken",
  "UnrelatedKeyIdInToken",
  "BadEnvironmentKeyIdInToken",
  "BadPath",
  "MethodNotAllowed",
  "ExpiredToken",
  "Unregistered",
  "PayloadTooLarge",
  "TooManyProviderTokenUpdates",
  "TooManyRequests",
  "InternalServerError",
  "ServiceUnavailable",
  "Shutdown",
  // Apple, the same page, for a channel of broadcast pushes: the first to fail when the capability or the key does not match.
  "FeatureNotEnabled",
  "MissingChannelId",
  "BadChannelId",
  "ChannelNotRegistered",
  "BadRequestParams",
  "BadRequestPayload",
  "MissingPushType",
  "CannotCreateChannelConfig",
  "TopicMismatch",
  // The server's own (`apns-client.ts`, `live-activity-starts.ts`).
  "no-answer",
  "server-error",
  "no-channel-id",
  "unreadable-key",
]);

/** The reason of an Apple answer with no reason in its body. */
const statusReason = /^status-\d{3}$/;

/**
 * The name under which the counts keep an answer: `started`, `already-started`, `not-set-up`, `bad-request`, or `refused:<reason>`.
 * It is a word of a short fixed list, so that a count holds no rider, no stop and no token.
 */
export function startAnswerName(answer: StartAnswer): string {
  if (answer.result === "refused") {
    const reason = answer.reason ?? "";
    return `refused:${reasons.has(reason) || statusReason.test(reason) ? reason : "other"}`;
  }
  return results.get(answer.result) ?? "other";
}
