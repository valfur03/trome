import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { contactEmail } from './contact.ts';
import { rulesForPage, withNoBreakSpacesInText } from './typography.ts';

// The store text page holds the texts that a maintainer pastes into App Store Connect and TestFlight, and one that a friend gets in Messages.
// Its page is in English, so the typography test of the pages gives it no French rule, and its texts sit in code blocks, which that test skips.
// This test reads each text as the reader pastes it: a French text keeps its no-break spaces (a line never starts with » or :),
// and each size that the page declares is the size of its text, counted with the real address, under the limit of its field.

const source = readFileSync(new URL('content/docs/en/maintain/store-text.mdx', import.meta.url), 'utf8');
const lines = source.split('\n');

interface StoreText {
  label: string;
  french: boolean;
  declared: number;
  limit?: number;
  unit: 'characters' | 'bytes';
  text: string;
}

// The text of a `<Code code={name} />` block: the template literal that the page exports under that name.
function exportedText(name: string): string {
  const start = `export const ${name} = \``;
  const from = source.indexOf(start);
  assert.ok(from >= 0, `the page exports no ${name}`);
  const textStart = from + start.length;
  const text = source.slice(textStart, source.indexOf('`;', textStart)).replaceAll('${contactEmail}', contactEmail);
  assert.ok(!text.includes('${'), `${name} holds a value that this test does not know, so its size cannot be counted`);
  return text;
}

// A text is a line that gives its size, as "French (99 of 100 bytes):" or a row of a table, then, within three lines, a code block or a `<Code code={name} />` block.
function storeTexts(): StoreText[] {
  const texts: StoreText[] = [];
  lines.forEach((line, index) => {
    const size = /\((\d+) (?:of (\d+) )?(bytes|characters)\)/.exec(line);
    if (!size) return;
    const start = lines.findIndex((candidate, at) => at > index && (candidate.startsWith('```') || candidate.startsWith('<Code ')));
    assert.ok(start > index && start - index <= 3, `${line}: no text under this line`);
    const next = lines[start];
    let text: string;
    if (next.startsWith('```')) {
      const end = lines.findIndex((candidate, at) => at > start && candidate.startsWith('```'));
      text = lines.slice(start + 1, end).join('\n');
    } else {
      const name = /code=\{(\w+)\}/.exec(next)?.[1];
      assert.ok(name, `${line}: no text under this line`);
      text = exportedText(name);
    }
    texts.push({
      label: line.slice(0, size.index + size[0].length),
      french: line.includes('French'),
      declared: Number(size[1]),
      limit: size[2] ? Number(size[2]) : undefined,
      unit: size[3] as StoreText['unit'],
      text,
    });
  });
  return texts;
}

const texts = storeTexts();
const french = rulesForPage('fr/store-text');

describe('the texts of the store text page', () => {
  it('finds every text that the page sizes', () => {
    assert.equal(texts.filter((text) => text.french).length, 8);
    assert.equal(texts.filter((text) => !text.french).length, 7);
  });

  for (const { label, french: isFrench, declared, limit, unit, text } of texts) {
    it(`${label} is the size of its text`, () => {
      const size = unit === 'bytes' ? Buffer.byteLength(text) : [...text].length;
      assert.equal(size, declared, `Write ${size} ${unit} in this line: the page says ${declared}.`);
      if (limit) assert.ok(size <= limit, `${size} ${unit} is over the limit of ${limit}.`);
      // A text of TestFlight that has no limit of its own stays under 1,000 bytes, as the page says.
      if (!limit && unit === 'bytes') assert.ok(size < 1000, `${size} bytes is not under 1,000 bytes: a no-break space takes two bytes, so cut words.`);
    });

    if (!isFrench) continue;
    it(`${label} has a no-break space at every place of the French rules`, () => {
      const faults = text
        .split('\n')
        .map((line) => ({ line, fixed: withNoBreakSpacesInText(line, french) }))
        .filter(({ line, fixed }) => line !== fixed)
        .map(({ line, fixed }) => line.split('').map((character, at) => (character === fixed[at] ? character : '⍽')).join(''));
      assert.deepEqual(faults, [], 'Replace each plain space marked ⍽ by a no-break space (U+00A0): before », :, ; ? and !, after «, between a number and its unit.');
    });
  }
});
