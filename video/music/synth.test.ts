import assert from 'node:assert/strict';
import {test} from 'node:test';
import {sampleRate, synth, wav} from './synth.ts';

test('the music lasts the asked time, on two channels', () => {
  const {left, right} = synth(2);
  assert.equal(left.length, 2 * sampleRate);
  assert.equal(right.length, 2 * sampleRate);
});

test('the music is loud, but never clips, and fades in and out', () => {
  const {left, right} = synth(2);
  const peak = [...left, ...right].reduce((max, x) => Math.max(max, Math.abs(x)), 0);
  assert.ok(peak > 0.85 && peak <= 0.9, `peak ${peak}`);
  assert.equal(left[0], 0);
  assert.ok(Math.abs(left[left.length - 1]) < 0.001);
});

test('the music is the same on every run', () => {
  assert.deepEqual(synth(1), synth(1));
});

test('the WAV file is stereo, 16 bits, at the sample rate of the synth', () => {
  const {left, right} = synth(1);
  const file = wav(left, right);
  assert.equal(file.toString('ascii', 0, 4), 'RIFF');
  assert.equal(file.toString('ascii', 8, 12), 'WAVE');
  assert.equal(file.readUInt16LE(22), 2);
  assert.equal(file.readUInt32LE(24), sampleRate);
  assert.equal(file.readUInt16LE(34), 16);
  assert.equal(file.readUInt32LE(40), sampleRate * 4);
  assert.equal(file.length, 44 + sampleRate * 4);
});
