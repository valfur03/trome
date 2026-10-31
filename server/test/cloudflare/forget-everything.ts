import { reset } from "cloudflare:test";
import { vi } from "vitest";

/**
 * Leaves nothing of a Cloudflare test to the next one: no server object, no row, no alarm, no fake.
 * `reset()` stops every object and wipes its storage in one step, so no timer or alarm of the object runs on storage whose tables are gone
 * (a wipe of the storage of a live object let its timer write to a deleted table: "no such table").
 * It runs before the fakes go, so that work still in flight never meets the real network.
 */
export async function forgetEverything(): Promise<void> {
  await reset();
  vi.useRealTimers();
  vi.restoreAllMocks();
}
