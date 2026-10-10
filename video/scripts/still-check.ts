// Usage: node scripts/still-check.ts <file.png>
// Fails unless the file is a PNG picture of the size of the film.
import {readFileSync} from 'node:fs';
import {film} from '../src/timing.ts';

const [file] = process.argv.slice(2);
if (!file) {
  console.error('Usage: node scripts/still-check.ts <file.png>');
  process.exit(2);
}
const png = readFileSync(file);
const fail = (reason: string) => {
  console.error(`${file}: ${reason}`);
  process.exit(1);
};
if (png.toString('latin1', 1, 4) !== 'PNG' || png.toString('ascii', 12, 16) !== 'IHDR') {
  fail('not a PNG picture');
}
const width = png.readUInt32BE(16);
const height = png.readUInt32BE(20);
if (width !== film.width || height !== film.height) {
  fail(`${width} x ${height}, but the film is ${film.width} x ${film.height}`);
}
console.log(`${file}: ${width} x ${height}, ${Math.round(png.length / 1024)} KB`);
