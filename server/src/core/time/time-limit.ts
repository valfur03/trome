/**
 * A limit of time for a piece of work: its signal aborts after `duration`, through `setTimeout`, so that the fake timers of a test move it.
 * `end` stops the timer when the work ends first: a timer left behind would keep a server object awake.
 */
export interface TimeLimit {
  signal: AbortSignal;
  end(): void;
}

export function timeLimit(duration: number): TimeLimit {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort(new DOMException("The time limit is over", "TimeoutError"));
  }, duration);
  return {
    signal: controller.signal,
    end: () => {
      clearTimeout(timer);
    },
  };
}

/** The result of `work`, or `late()` as soon as `signal` aborts: the work goes on, and only its result is lost here. */
export function beforeAbort<T>(work: Promise<T>, signal: AbortSignal, late: () => T): Promise<T> {
  if (signal.aborted) {
    return Promise.resolve(late());
  }
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => {
      resolve(late());
    };
    signal.addEventListener("abort", onAbort, { once: true });
    work.then(
      (value) => {
        signal.removeEventListener("abort", onAbort);
        resolve(value);
      },
      (error: unknown) => {
        signal.removeEventListener("abort", onAbort);
        reject(error instanceof Error ? error : new Error(String(error)));
      },
    );
  });
}
