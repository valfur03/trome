import type { PrimBudget } from "../budget/prim-budget";
import type { RelaySettings } from "../config/relay-settings";
import type { Logger } from "../logging/logger";
import type { Clock } from "../time/clock";
import { parisDay } from "../time/paris-time";
import type { MetricsSnapshot } from "../metrics/prometheus-metrics";
import type { UsageCounts, UsageReport } from "../usage/usage-counts";
import type { AnswerStore, StoredAnswer } from "./answer-store";
import { readPrimAnswer } from "./prim-answer";
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
    this.forgetStopsPastUse(now);

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
    this.forgetStopsPastUse(clock.now());
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

  metrics(): MetricsSnapshot {
    const { usage, budget, clock } = this.dependencies;
    this.forgetStopsPastUse(clock.now());
    return { ...usage.metricsTotals(clock.now()), dailyCap: budget.dailyCap };
  }

  /** Forgets the answers and the failures that are past their use: the server object calls it at its own timer, when no request comes. */
  forgetPastUse(): void {
    this.forgetStopsPastUse(this.dependencies.clock.now());
  }

  /**
   * The next time at which something in memory stops being of use: an answer reaches the oldest age at which the server gives it (5 minutes), or a failed stop ends its pause.
   * Until then, a sleep of the server object, which empties its memory, would cost a PRIM call or end a pause early: so the object keeps a timer to this time, and asks again then.
   * While that timer keeps the object awake anyway, it also comes at the end of the 10 minutes of each answer, so that no answer stays in memory longer.
   * Undefined when a sleep loses nothing that the server still uses.
   */
  nextUseEnd(): number | undefined {
    const { answers, clock, settings } = this.dependencies;
    const now = clock.now();
    const useEnds = [
      ...answers.answeredTimes().map((answeredAt) => answeredAt + longestAnswerAge(settings)),
      ...[...this.lastFailureAt.values()].map((failedAt) => failedAt + settings.pauseAfterFailure),
    ].filter((end) => end > now);
    if (useEnds.length === 0) {
      return undefined;
    }
    const awakeUntil = Math.max(...useEnds);
    const forgetTimes = answers
      .answeredTimes()
      .map((answeredAt) => answeredAt + settings.startAge)
      .filter((end) => end > now && end < awakeUntil);
    return Math.min(...useEnds, ...forgetTimes);
  }

  stopsInMemory(): string[] {
    const { answers } = this.dependencies;
    return [...new Set([...answers.stopsHeld(), ...this.lastFailureAt.keys(), ...this.inFlight.keys()])];
  }

  private forgetStopsPastUse(now: number): void {
    const { answers, settings } = this.dependencies;
    answers.forgetAnswersGivenBy(now - settings.startAge);
    for (const [stopRef, failedAt] of this.lastFailureAt) {
      if (failedAt + settings.pauseAfterFailure <= now) {
        this.lastFailureAt.delete(stopRef);
      }
    }
  }

  private pause(stopRef: string, now: number): Pause | undefined {
    const { answers, budget, settings } = this.dependencies;
    const pauses: Pause[] = [];
    const limitUntil = answers.limitPauseUntil();
    if (limitUntil > now) {
      pauses.push({ reason: "prim-limit", until: limitUntil + retrySpread(stopRef, limitUntil, settings.retrySpread) });
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
    const retryFrom = budget.retryAt(now);
    return { reason: "budget", until: retryFrom + retrySpread(stopRef, retryFrom, settings.retrySpread) };
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
    usage.countPrimCall(startedAt);

    const reply = await prim.stopMonitoring(stopRef).catch(
      (error: unknown): PrimReply => ({ kind: "unreachable", reason: error instanceof Error ? error.name : "unknown" }),
    );
    const at = clock.now();

    const reading = reply.kind === "answer" && reply.status >= 200 && reply.status < 300 ? readPrimAnswer(reply.body) : undefined;
    if (reading && !reading.hasBuildShape) {
      usage.count("unreadableAnswers", at);
    }

    if (reply.kind === "answer" && reading?.isTimes) {
      const answer = { body: reply.body, primAnsweredAt: at };
      answers.keep(stopRef, answer);
      this.lastFailureAt.delete(stopRef);
      return times(answer);
    }

    if (reply.kind === "answer" && reply.status === 429) {
      answers.pauseForLimitUntil(at + settings.pauseAfterLimit);
      this.recordError(at, "prim-limit", reply.status);
      return this.answerWhilePaused(stopRef, this.pause(stopRef, at) ?? this.budgetPause(stopRef, at), at);
    }

    this.lastFailureAt.set(stopRef, at);
    this.recordError(at, failureKind(reply), reply.kind === "answer" ? reply.status : null);
    return this.answerWhilePaused(stopRef, this.pause(stopRef, at) ?? this.budgetPause(stopRef, at), at);
  }

  private recordError(at: number, kind: string, status: number | null): void {
    this.dependencies.usage.recordError({ at, kind, status });
    this.dependencies.logger.error("prim-call-failed", { kind, status });
  }

  private tidy(now: number): void {
    const today = parisDay(now);
    if (this.lastTidyDay === today) {
      return;
    }
    this.lastTidyDay = today;
    const { budget, usage } = this.dependencies;
    usage.forgetOldCounts(now);
    budget.forgetDaysBefore(today);
  }
}

/** The oldest age at which the server gives an answer: 5 minutes, when PRIM fails or the budget is short. */
function longestAnswerAge(settings: RelaySettings): number {
  return Math.max(settings.freshAge, settings.heldAge, ...settings.agedAnswers.map((step) => step.age));
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
