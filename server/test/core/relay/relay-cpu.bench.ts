import { bench, describe } from "vitest";
import { hasBearerToken } from "../../../src/core/auth/bearer-token";
import { departuresResponse } from "../../../src/core/http/relay-responses";
import { AnswerStore } from "../../../src/core/relay/answer-store";
import { isTimesAnswer } from "../../../src/core/relay/prim-answer";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { primFixture } from "./prim-fixtures";

interface Answer {
  Siri: { ServiceDelivery: { StopMonitoringDelivery: { MonitoredStopVisit: unknown[] }[] } };
}

const biggestRecorded = primFixture("stop-monitoring-vincennes-rer-a-2139.json");

function answerWithVisits(count: number): string {
  const answer = JSON.parse(primFixture("stop-monitoring-abbesses-stop-area.json")) as Answer;
  const [delivery] = answer.Siri.ServiceDelivery.StopMonitoringDelivery;
  const visits = delivery?.MonitoredStopVisit ?? [];
  if (delivery) {
    delivery.MonitoredStopVisit = Array.from({ length: count }, (_, index) => visits[index % visits.length]);
  }
  return JSON.stringify(answer, null, 2);
}

const answers = {
  [`biggest recorded answer (${String(biggestRecorded.length)} bytes)`]: biggestRecorded,
  ...Object.fromEntries(
    [100, 400].map((count) => {
      const body = answerWithVisits(count);
      return [`answer of ${String(count)} visits (${String(body.length)} bytes)`, body];
    }),
  ),
};

const headers = new Headers({ authorization: "Bearer app-token-of-the-bench-0123456789abcdef" });

for (const [name, body] of Object.entries(answers)) {
  describe(name, () => {
    const store = new AnswerStore(new NodeSqliteDatabase());

    bench("object: check and keep a new PRIM answer, then answer", async () => {
      if (!isTimesAnswer(body)) {
        throw new Error("not a times answer");
      }
      store.keep("STIF:StopArea:SP:462374:", { body, primAnsweredAt: 1 });
      await departuresResponse({ kind: "times", body, primAnsweredAt: 1 }, 2).text();
    });

    bench("object: give the shared answer", async () => {
      const held = store.answer("STIF:StopArea:SP:462374:") ?? { body, primAnsweredAt: 1 };
      await departuresResponse({ kind: "times", ...held }, 2).text();
    });

    bench("worker: check the token and build the answer", async () => {
      hasBearerToken(headers, "app-token-of-the-bench-0123456789abcdef");
      await departuresResponse({ kind: "times", body, primAnsweredAt: 1 }, 2).text();
    });
  });
}
