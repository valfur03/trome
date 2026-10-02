import type { PrimBudget } from "../budget/prim-budget";
import type { RelaySettings } from "../config/relay-settings";
import type { Logger } from "../logging/logger";
import { day, type Clock } from "../time/clock";
import { parisDay } from "../time/paris-time";
import type { UsageCounts, UsageReport } from "../usage/usage-counts";
import type { AnswerStore, StoredAnswer } from "./answer-store";
import { isTimesAnswer } from "./prim-answer";
import type { PrimClient, PrimReply } from "./prim-client";
import { retrySpread } from "./retry-spread";

export type OutReason = "budget" | "prim-limit" | "prim-failure";

export type RelayAnswer =
  | { kind: "times"; body: string; primAnsweredAt: number }
  | { kind: "out"; reason: OutReason; retryAt: number };

export interface CountsReport extends UsageReport {
  today: string;
  dailyCap: number;
  primCallsToday: number;
  limitPauseUntil: string | null;
}

export interface RelayDependencies {
  answers: AnswerStore;
  budget: PrimBudget;
  usage: UsageCounts;
  prim: PrimClient;
  clock: Clock;
  logger: Logger;
  settings: RelaySettings;
}

interface Pause {
  reason: OutReason;
  until: number;
}

export class Relay {
  private readonly inFlight = new Map<string, Promise<RelayAnswer>>();
  private readonly lastFailureAt = new Map<string, number>();
  private lastTidyDay: string | undefined;

  constructor(private readonly dependencies: RelayDependencies) {}

  departures(stopRef: string): Promise<RelayAnswer> {
    const { answers, budget, usage, clock, settings } = this.dependencies;
    const now = clock.now();
    usage.count("appCalls", now);

    const held = answers.answer(stopRef);
    const age = held ? now - held.primAnsweredAt : Number.POSITIVE_INFINITY;
    if (held && age < settings.freshAge) {
      usage.count("cacheHits", now);
      return Promise.resolve(times(held));
    }

    const call = this.inFlight.get(stopRef);
    if (call) {
      usage.count("cacheHits", now);
      return call;
    }

    const pause = this.pause(stopRef, now);
    if (pause) {
      return Promise.resolve(this.answerWhilePaused(stopRef, pause, now));
    }

    if (held && age < budget.answerAge(now)) {
      usage.count("cacheHits", now);
      return Promise.resolve(times(held));
    }

    if (!budget.claim(now, age < settings.startAge ? "refresh" : "start")) {
      return Promise.resolve(this.answerWhilePaused(stopRef, this.budgetPause(stopRef, now), now));
    }

    const newCall = this.callPrim(stopRef, now).finally(() => this.inFlight.delete(stopRef));
    this.inFlight.set(stopRef, newCall);
    return newCall;
  }

  counts(): CountsReport {
    const { answers, budget, usage, clock } = this.dependencies;
    const today = parisDay(clock.now());
    const limitPauseUntil = answers.limitPauseUntil();
    return {
      today,
      dailyCap: budget.dailyCap,
      primCallsToday: budget.used(today),
      limitPauseUntil: limitPauseUntil > clock.now() ? new Date(limitPauseUntil).toISOString() : null,
      ...usage.report(),
    };
  }

  private pause(stopRef: string, now: number): Pause | undefined {
    const { answers, budget, settings } = this.dependencies;
    const pauses: Pause[] = [];
    const limitUntil = answers.limitPauseUntil();
    if (limitUntil > now) {
      pauses.push({ reason: "prim-limit", until: limitUntil + retrySpread(stopRef, settings.retrySpread) });
    }
    const failedAt = this.lastFailureAt.get(stopRef);
    if (failedAt !== undefined && failedAt + settings.pauseAfterFailure > now) {
      pauses.push({ reason: "prim-failure", until: failedAt + settings.pauseAfterFailure });
    }
    if (pauses.length > 0 && budget.hasNoCallLeft(now)) {
      pauses.push(this.budgetPause(stopRef, now));
    }
    return pauses.reduce<Pause | undefined>((latest, pause) => (latest && latest.until >= pause.until ? latest : pause), undefined);
  }

  private budgetPause(stopRef: string, now: number): Pause {
    const { budget, settings } = this.dependencies;
    return { reason: "budget", until: budget.retryAt(now) + retrySpread(stopRef, settings.retrySpread) };
  }

  private answerWhilePaused(stopRef: string, pause: Pause, now: number): RelayAnswer {
    const { answers, usage, settings } = this.dependencies;
    const held = answers.answer(stopRef);
    if (held && now - held.primAnsweredAt < settings.heldAge) {
      usage.count("heldAnswers", now);
      return times(held);
    }
    usage.count("outAnswers", now);
    return { kind: "out", reason: pause.reason, retryAt: pause.until };
  }

  private async callPrim(stopRef: string, startedAt: number): Promise<RelayAnswer> {
    const { answers, usage, prim, clock, settings } = this.dependencies;
    this.tidy(startedAt);
    usage.countPrimCall(stopRef, startedAt);

    const reply = await prim.stopMonitoring(stopRef).catch(
      (error: unknown): PrimReply => ({ kind: "unreachable", reason: error instanceof Error ? error.name : "unknown" }),
    );
    const at = clock.now();

    if (reply.kind === "answer" && reply.status >= 200 && reply.status < 300 && isTimesAnswer(reply.body)) {
      const answer = { body: reply.body, primAnsweredAt: at };
      answers.keep(stopRef, answer);
      this.lastFailureAt.delete(stopRef);
      return times(answer);
    }

    if (reply.kind === "answer" && reply.status === 429) {
      answers.pauseForLimitUntil(at + settings.pauseAfterLimit);
      this.recordError(stopRef, at, "prim-limit", reply.status);
      return this.answerWhilePaused(stopRef, this.pause(stopRef, at) ?? this.budgetPause(stopRef, at), at);
    }

    this.lastFailureAt.set(stopRef, at);
    this.recordError(stopRef, at, failureKind(reply), reply.kind === "answer" ? reply.status : null);
    return this.answerWhilePaused(stopRef, this.pause(stopRef, at) ?? this.budgetPause(stopRef, at), at);
  }

  private recordError(stopRef: string, at: number, kind: string, status: number | null): void {
    this.dependencies.usage.recordError({ at, stopRef, kind, status });
    this.dependencies.logger.error("prim-call-failed", { stopRef, kind, status });
  }

  private tidy(now: number): void {
    const today = parisDay(now);
    if (this.lastTidyDay === today) {
      return;
    }
    this.lastTidyDay = today;
    const { answers, budget, usage, settings } = this.dependencies;
    usage.forgetOldCounts(now);
    budget.forgetDaysBefore(today);
    answers.forgetAnswersBefore(now - day);
    for (const [stopRef, failedAt] of this.lastFailureAt) {
      if (failedAt + settings.pauseAfterFailure <= now) {
        this.lastFailureAt.delete(stopRef);
      }
    }
  }
}

function times(answer: StoredAnswer): RelayAnswer {
  return { kind: "times", body: answer.body, primAnsweredAt: answer.primAnsweredAt };
}

function failureKind(reply: PrimReply): string {
  if (reply.kind === "unreachable") {
    return reply.reason === "TimeoutError" ? "prim-timeout" : "prim-unreachable";
  }
  return reply.status >= 200 && reply.status < 300 ? "prim-error-body" : "prim-http-error";
}
