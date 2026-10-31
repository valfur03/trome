import { afterEach, beforeEach, expect } from "vitest";
import { RelayObject } from "../../src/cloudflare/relay-object";

// A setup file of the Cloudflare tests (vitest.config.ts).
// An alarm that workerd runs on its own prints its error to the log, retries it, and fails no test.
// So a test runs each alarm of the server object with runDurableObjectAlarm, where its error fails the test,
// and plans it after the real now (a fake time in the past puts it in the past, where workerd runs it at once).
// This file fails the test in which workerd ran one on its own, with the error that it threw.

const ranOnTheirOwn: string[] = [];
const alarm = RelayObject.prototype.alarm;

RelayObject.prototype.alarm = async function (this: RelayObject, ...details: Parameters<typeof alarm>): Promise<void> {
  // workerd gives the details of the alarm; runDurableObjectAlarm gives none.
  if (details[0] === undefined) {
    return alarm.apply(this, details);
  }
  ranOnTheirOwn.push("an alarm of the server object ran on its own");
  try {
    await alarm.apply(this, details);
  } catch (error) {
    ranOnTheirOwn.push(`it threw: ${String(error)}`);
    throw error;
  }
};

beforeEach(() => {
  ranOnTheirOwn.length = 0;
});

afterEach(() => {
  expect(ranOnTheirOwn, "plan the alarm after the real now, and run it with runDurableObjectAlarm").toEqual([]);
});
