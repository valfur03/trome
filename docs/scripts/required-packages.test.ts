import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { brokenPackages } from './required-packages.ts';

describe('brokenPackages', () => {
  it('finds no broken package when each one loads', async () => {
    assert.deepEqual(await brokenPackages(['a', 'b'], async () => ({})), []);
  });

  it('names each package that does not load, with the reason', async () => {
    const load = async (name: string) => {
      if (name === 'b') {
        throw new Error("Cannot find package '@emnapi/runtime'");
      }
      return {};
    };
    assert.deepEqual(await brokenPackages(['a', 'b'], load), [{ name: 'b', reason: "Cannot find package '@emnapi/runtime'" }]);
  });
});
