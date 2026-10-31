// Usage: node scripts/name-stills.ts <folder>
// Gives each PNG of a render of the Stills composition the name of its key frame (fr-a-1-light.png, ...), in the
// order of keyFrames, so that a reader finds a frame by its language, its look and its beat.
import {readdirSync, renameSync} from 'node:fs';
import {join} from 'node:path';
import {keyFrameName, keyFrames} from '../src/arrival.ts';

const [folder] = process.argv.slice(2);
if (!folder) {
  console.error('Usage: node scripts/name-stills.ts <folder>');
  process.exit(2);
}
const rendered = readdirSync(folder)
  .filter((name) => name.endsWith('.png') && !name.startsWith('storyboard'))
  .sort();
if (rendered.length !== keyFrames.length) {
  console.error(`${folder} has ${rendered.length} key frames, but the storyboard has ${keyFrames.length}`);
  process.exit(1);
}
rendered.forEach((name, i) => renameSync(join(folder, name), join(folder, `${keyFrameName(keyFrames[i])}.png`)));
console.log(`Named ${rendered.length} key frames in ${folder}`);
