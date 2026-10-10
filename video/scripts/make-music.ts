// Usage: node scripts/make-music.ts <file.wav>
// Writes the music of the film, as long as the film.
import {mkdirSync, writeFileSync} from 'node:fs';
import {dirname} from 'node:path';
import {synth, wav} from '../music/synth.ts';
import {film} from '../src/timing.ts';

const [file] = process.argv.slice(2);
if (!file) {
  console.error('Usage: node scripts/make-music.ts <file.wav>');
  process.exit(2);
}
const {left, right} = synth(film.seconds);
mkdirSync(dirname(file), {recursive: true});
writeFileSync(file, wav(left, right));
