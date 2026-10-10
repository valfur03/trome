// A music clip made only in code: no sample, no loop and no sound of anyone else, so it is under the licence of the repo.
// Am - F - C - G at 112 beats a minute: a soft pad, a plucked arpeggio, a bass, a kick and a hi-hat.

export const sampleRate = 48000;

const beat = 60 / 112;
const bar = 4 * beat;
// Am, F, C, G, as MIDI note numbers.
const chords = [
  [57, 60, 64],
  [53, 57, 60],
  [48, 52, 55],
  [55, 59, 62],
];
// The loudest sample, a little under full scale.
const peakLevel = 0.89;

type Voice = (t: number) => number;

const hz = (midi: number) => 440 * 2 ** ((midi - 69) / 12);
const sine = (frequency: number, t: number) => Math.sin(2 * Math.PI * frequency * t);

const pad =
  (frequency: number, length: number): Voice =>
  (t) =>
    Math.min(1, t / 0.6, (length - t) / 0.4) * ([0.996, 1, 1.004].reduce((sum, detune) => sum + sine(frequency * detune, t), 0) / 3);
const pluck =
  (frequency: number): Voice =>
  (t) =>
    Math.exp(-t * 7) * (sine(frequency, t) + 0.3 * sine(2 * frequency, t));
const bass =
  (frequency: number): Voice =>
  (t) =>
    Math.exp(-t * 3) * (sine(frequency, t) + 0.2 * sine(3 * frequency, t));
const kick: Voice = (t) => Math.exp(-t * 18) * Math.sin(2 * Math.PI * (45 * t + (75 * (1 - Math.exp(-t * 30))) / 30));

// A small seeded random generator (mulberry32): the same noise, so the same file, on every run.
function random(seed: number) {
  let state = seed;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let x = Math.imul(state ^ (state >>> 15), 1 | state);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

function hat(next: () => number): Voice {
  let previous = 0;
  return (t) => {
    const noise = next() * 2 - 1;
    const value = noise - previous;
    previous = noise;
    return Math.exp(-t * 60) * value;
  };
}

// Returns the two channels, each sample between -1 and 1, with a short fade in and a fade out at the end.
export function synth(seconds: number): {left: Float32Array; right: Float32Array} {
  const count = Math.round(sampleRate * seconds);
  const left = new Float64Array(count);
  const right = new Float64Array(count);
  const next = random(7);

  const add = (start: number, length: number, voice: Voice, gain: number, pan = 0) => {
    const first = Math.round(start * sampleRate);
    const last = Math.min(count, Math.round((start + length) * sampleRate));
    const leftGain = (gain * (1 - pan) * Math.SQRT2) / 2;
    const rightGain = (gain * (1 + pan) * Math.SQRT2) / 2;
    for (let i = first; i < last; i++) {
      const value = voice((i - first) / sampleRate);
      left[i] += value * leftGain;
      right[i] += value * rightGain;
    }
  };

  for (let k = 0; k * bar < seconds; k++) {
    const chord = chords[k % chords.length];
    const start = k * bar;
    for (const note of chord) {
      add(start, bar, pad(hz(note + 12), bar), 0.1);
    }
    const arpeggio = [...chord, chord[0] + 12, chord[1] + 12];
    [0, 1, 2, 3, 4, 3, 2, 1].forEach((index, step) => {
      add(start + (step * beat) / 2, 0.5, pluck(hz(arpeggio[index] + 12)), 0.09, step % 2 ? -0.4 : 0.4);
    });
    for (let b = 0; b < 4; b++) {
      add(start + b * beat, beat, bass(hz(chord[0] - 12)), 0.22);
      if (b % 2 === 0) {
        add(start + b * beat, 0.4, kick, 0.5);
      }
      add(start + b * beat + beat / 2, 0.1, hat(next), 0.05, 0.2);
    }
  }

  let peak = 0;
  for (let i = 0; i < count; i++) {
    peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
  }
  const out = {left: new Float32Array(count), right: new Float32Array(count)};
  for (let i = 0; i < count; i++) {
    const fade = Math.min(1, i / (0.05 * sampleRate), (count - i) / (0.8 * sampleRate));
    out.left[i] = (peakLevel * fade * left[i]) / peak;
    out.right[i] = (peakLevel * fade * right[i]) / peak;
  }
  return out;
}

// A WAV file: stereo, 16 bits, at the sample rate of the synth.
export function wav(left: Float32Array, right: Float32Array): Buffer {
  const dataSize = left.length * 4;
  const file = Buffer.alloc(44 + dataSize);
  file.write('RIFF', 0, 'ascii');
  file.writeUInt32LE(36 + dataSize, 4);
  file.write('WAVE', 8, 'ascii');
  file.write('fmt ', 12, 'ascii');
  file.writeUInt32LE(16, 16);
  file.writeUInt16LE(1, 20);
  file.writeUInt16LE(2, 22);
  file.writeUInt32LE(sampleRate, 24);
  file.writeUInt32LE(sampleRate * 4, 28);
  file.writeUInt16LE(4, 32);
  file.writeUInt16LE(16, 34);
  file.write('data', 36, 'ascii');
  file.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < left.length; i++) {
    file.writeInt16LE(Math.round(left[i] * 32767), 44 + i * 4);
    file.writeInt16LE(Math.round(right[i] * 32767), 46 + i * 4);
  }
  return file;
}
