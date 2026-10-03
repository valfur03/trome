import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkWarnings, warningLines } from './build-warnings.ts';
import { knownBuildWarnings } from './known-build-warnings.ts';

const known = [{ text: 'module level directive "use astro:head-inject"', reason: 'a tool bug', upstream: 'https://example.com/1' }];
const knownLine =
  '09:46:10 [WARN] [vite] \u001b[33m[MODULE_LEVEL_DIRECTIVE] \u001b[0mThe semantics of the module level directive "use astro:head-inject" in "src/content/docs/fr/index.mdx" may not be preserved when bundling.';
const newLine = '09:46:10   ├─ /404.html09:46:10 [WARN] [content] Entry docs → 404 was not found.';

describe('warningLines', () => {
  it('finds the warnings of Astro, of Astro in the background, of npm and of Node', () => {
    const output = [
      '09:46:09 [build] output: "static"',
      knownLine,
      '{"message":"Entry docs → 404 was not found.","label":"content","level":"warn"}',
      'npm warn allow-scripts esbuild@0.28.2 (postinstall: node install.js)',
      '(node:123) ExperimentalWarning: something',
      '- 0 warnings',
    ].join('\n');
    assert.equal(warningLines(output).length, 4);
  });

  it('removes the colors of the terminal', () => {
    assert.ok(!warningLines(knownLine)[0].includes('\u001b'));
  });
});

describe('checkWarnings', () => {
  it('passes a build with no warning when no warning is known', () => {
    assert.deepEqual(checkWarnings('09:46:16 [build] Complete!', []), { unknown: [], known: [], stale: [] });
  });

  it('reports a warning that is not in the list', () => {
    assert.deepEqual(checkWarnings(`${knownLine}\n${newLine}`, known).unknown, [newLine.trim()]);
  });

  it('accepts each warning of the list, also when the build prints it for many pages', () => {
    const report = checkWarnings(`${knownLine}\n${knownLine}`, known);
    assert.deepEqual(report.unknown, []);
    assert.equal(report.known.length, 2);
  });

  it('reports an entry of the list that the build no longer prints', () => {
    assert.deepEqual(checkWarnings('09:46:16 [build] Complete!', known).stale, known);
  });
});

describe('the list of known warnings', () => {
  it('gives the reason and the upstream link of each entry', () => {
    for (const { text, reason, upstream } of knownBuildWarnings) {
      assert.ok(text.length > 0 && reason.length > 0, text);
      assert.match(upstream, /^https:\/\//, text);
    }
  });
});
