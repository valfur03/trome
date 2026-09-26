import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseTicks, progressLabel, serializeTicks } from './checklist.ts';

describe('progressLabel', () => {
  it('counts the steps done', () => {
    assert.equal(progressLabel(3, 11), '3 of 11 steps done');
  });

  it('uses the singular for a list of one step', () => {
    assert.equal(progressLabel(0, 1), '0 of 1 step done');
  });
});

describe('parseTicks', () => {
  it('ticks the saved steps', () => {
    assert.deepEqual(parseTicks('[0,2]', 3), [true, false, true]);
  });

  it('ticks nothing when nothing is saved', () => {
    assert.deepEqual(parseTicks(null, 2), [false, false]);
  });

  it('ticks nothing when the saved value is not valid', () => {
    assert.deepEqual(parseTicks('{oops', 2), [false, false]);
    assert.deepEqual(parseTicks('{"a":1}', 2), [false, false]);
  });

  it('ignores the steps that the list no longer has', () => {
    assert.deepEqual(parseTicks('[1,5,-1,0.5,"0"]', 2), [false, true]);
  });
});

describe('serializeTicks', () => {
  it('saves the indexes of the ticked steps', () => {
    assert.equal(serializeTicks([true, false, true]), '[0,2]');
  });

  it('reads back what it saves', () => {
    const ticks = [false, true, true, false];
    assert.deepEqual(parseTicks(serializeTicks(ticks), ticks.length), ticks);
  });
});
