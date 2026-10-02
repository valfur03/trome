import type { RelayAnswer } from "../relay/relay";

const noStore = { "cache-control": "no-store" };

export function departuresResponse(answer: RelayAnswer, now: number): Response {
  if (answer.kind === "times") {
    return new Response(answer.body, {
      headers: {
        ...noStore,
        "content-type": "application/json",
        "last-modified": new Date(answer.primAnsweredAt).toUTCString(),
      },
    });
  }
  return Response.json(
    { status: "out", reason: answer.reason, retryAt: new Date(answer.retryAt).toISOString() },
    {
      status: 503,
      headers: { ...noStore, "retry-after": String(Math.max(0, Math.ceil((answer.retryAt - now) / 1000))) },
    },
  );
}

export function errorResponse(status: number, error: string, headers: Record<string, string> = {}): Response {
  return Response.json({ error }, { status, headers: { ...noStore, ...headers } });
}
