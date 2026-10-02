import type { PrimClient, PrimReply } from "../../../src/core/relay/prim-client";
import { primFixture } from "./prim-fixtures";

interface PendingCall {
  stopRef: string;
  reply: (reply: PrimReply) => void;
}

export class FakePrimClient implements PrimClient {
  readonly calls: string[] = [];
  private readonly pending: PendingCall[] = [];
  private next: (stopRef: string) => PrimReply | "wait" = () => ({
    kind: "answer",
    status: 200,
    body: primFixture("stop-monitoring-abbesses-stop-area.json"),
  });

  answerWith(next: (stopRef: string) => PrimReply | "wait"): void {
    this.next = next;
  }

  stopMonitoring(stopRef: string): Promise<PrimReply> {
    this.calls.push(stopRef);
    const reply = this.next(stopRef);
    if (reply !== "wait") {
      return Promise.resolve(reply);
    }
    return new Promise((resolve) => {
      this.pending.push({ stopRef, reply: resolve });
    });
  }

  get waiting(): number {
    return this.pending.length;
  }

  release(reply: PrimReply = { kind: "answer", status: 200, body: primFixture("stop-monitoring-abbesses-stop-area.json") }): void {
    for (const call of this.pending.splice(0)) {
      call.reply(reply);
    }
  }
}

export function answer(status: number, body: string): PrimReply {
  return { kind: "answer", status, body };
}
