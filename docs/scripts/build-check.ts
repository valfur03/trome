import { spawn } from 'node:child_process';
import { checkWarnings } from './build-warnings.ts';
import { knownBuildWarnings } from './known-build-warnings.ts';
import { missingIcons } from './site-icon.ts';

const listFile = 'docs/scripts/known-build-warnings.ts';

const build = spawn('npm', ['run', 'build'], { stdio: ['ignore', 'pipe', 'pipe'] });
let output = '';
build.stdout.on('data', (chunk: Buffer) => {
  output += chunk.toString();
  process.stdout.write(chunk);
});
build.stderr.on('data', (chunk: Buffer) => {
  output += chunk.toString();
  process.stderr.write(chunk);
});

build.on('close', (code) => {
  if (code !== 0) {
    process.exit(code ?? 1);
  }
  const { unknown, known, stale } = checkWarnings(output, knownBuildWarnings);
  let failed = false;
  if (unknown.length > 0) {
    console.error(`\nThe docs build printed ${unknown.length} warning(s). Fix the cause of each one:`);
    unknown.forEach((line) => console.error(`  ${line}`));
    console.error(`Only a bug of a tool with no fixed version may go in ${listFile}, with its reason and upstream link.`);
    failed = true;
  }
  if (stale.length > 0) {
    console.error(`\nThe docs build no longer prints these known warnings, so remove them from ${listFile}:`);
    stale.forEach(({ text, upstream }) => console.error(`  ${text} (${upstream})`));
    failed = true;
  }
  const noIcon = missingIcons('dist');
  if (noIcon.length > 0) {
    console.error(`\n${noIcon.length} page(s) of the site link to no icon file, so the browser tab shows a blank icon. Set favicon in docs/astro.config.mjs to a file of docs/public/:`);
    noIcon.forEach((line) => console.error(`  ${line}`));
    failed = true;
  }
  if (failed) {
    process.exit(1);
  }
  if (known.length > 0) {
    const links = [...new Set(knownBuildWarnings.map(({ upstream }) => upstream))].join(', ');
    console.log(`\nThe docs build printed no new warning, and ${known.length} known warning(s) of a tool bug (${links}), listed in ${listFile}.`);
  } else {
    console.log('\nThe docs build printed no warning.');
  }
});
