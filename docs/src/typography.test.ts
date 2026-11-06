import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { noBreakClass, noBreakWordsPlugin, splitAtWords, withNoBreakHyphens, withNoBreakHyphensInToc } from './no-break-words.ts';
import { inPieces, noBreakSpace as nb, rulesForPage, typographyFaults, withNoBreakSpaces, withNoBreakSpacesInText } from './typography.ts';

// What each test is for: a French reader on a phone never meets a line that starts with », :, ;, ? or ! or ends with «,
// and never meets a number alone on a line with its unit on the next one.

const fr = rulesForPage('fr/support');
const en = rulesForPage('en/support');

describe('rulesForPage', () => {
  it('gives the French typography to every French page, and the units to the riders pages of both languages', () => {
    assert.deepEqual(fr, { highPunctuation: true, units: true });
    assert.deepEqual(en, { highPunctuation: false, units: true });
  });

  it('leaves the English pages of a section for a desk with their lines as they are', () => {
    assert.deepEqual(rulesForPage('en/maintain/store-text'), { highPunctuation: false, units: false });
    assert.deepEqual(rulesForPage('en/build/install-on-your-iphone'), { highPunctuation: false, units: false });
  });
});

describe('withNoBreakSpaces, French punctuation', () => {
  it('keeps each of », :, ;, ? and ! on the line of its word', () => {
    for (const mark of ['»', ':', ';', '?', '!']) {
      assert.equal(withNoBreakSpaces(`Un mot ${mark} la suite`, fr), `Un mot${nb}${mark} la suite`);
    }
  });

  it('keeps « with the word after it, and » with the word before it, in a text and in a heading', () => {
    assert.equal(withNoBreakSpaces('Que montre « Voir un exemple »', fr), `Que montre «${nb}Voir un exemple${nb}»`);
    assert.equal(withNoBreakSpaces('## Que montre « Voir un exemple » ?', fr), `## Que montre «${nb}Voir un exemple${nb}»${nb}?`);
  });

  it('does the same inside an attribute and a frontmatter value', () => {
    assert.equal(withNoBreakSpaces('alt: "Un écran : un train"', fr), `alt: "Un écran${nb}: un train"`);
    assert.equal(withNoBreakSpaces('<A caption="Ligne 7 : Pont Neuf" />', fr), `<A caption="Ligne 7${nb}: Pont Neuf" />`);
  });

  it('leaves what has no plain space to change', () => {
    assert.equal(withNoBreakSpaces(`Déjà${nb}: bon`, fr), `Déjà${nb}: bon`);
    assert.equal(withNoBreakSpaces('Un lien https://example.org/a?b=1 et 14:59', fr), 'Un lien https://example.org/a?b=1 et 14:59');
    assert.equal(withNoBreakSpaces('key: value', fr), 'key: value');
  });

  it('leaves the row under the head of a table: a no-break space before its colon would end the table', () => {
    for (const row of ['| :--- | ---: |', '| --- | :---: |', ':--- | ---:', '|:-|-:|']) assert.equal(withNoBreakSpaces(row, fr), row);
    assert.equal(withNoBreakSpaces('| Ligne : 1 | 3 min |', fr), `| Ligne${nb}: 1 | 3${nb}min |`);
  });

  it('leaves an indented line that starts with a mark: it is no word before a mark', () => {
    assert.equal(withNoBreakSpaces('  :::note', fr), '  :::note');
  });

  it('leaves an inline code and a code block as they are: the reader copies them', () => {
    assert.equal(withNoBreakSpaces('Tapez `a ? b : c` : puis `x ; y`', fr), `Tapez \`a ? b : c\`${nb}: puis \`x ; y\``);
    assert.equal(withNoBreakSpaces('```sh\necho a ; echo b\n```\nSuite :', fr), `\`\`\`sh\necho a ; echo b\n\`\`\`\nSuite${nb}:`);
    assert.equal(withNoBreakSpaces('~~~\nUn ? deux\n~~~', fr), '~~~\nUn ? deux\n~~~');
    assert.equal(withNoBreakSpaces('import X from "a : b";', fr), 'import X from "a : b";');
  });

  it('applies none of it on an English page', () => {
    assert.equal(withNoBreakSpaces('Step 1 : do this ? yes', en), 'Step 1 : do this ? yes');
  });
});

describe('withNoBreakSpaces, a number and its unit', () => {
  it('keeps the number with its unit, in French and in English', () => {
    assert.equal(withNoBreakSpaces('à 150 mètres de la station', fr), `à 150${nb}mètres de la station`);
    assert.equal(withNoBreakSpaces('within 150 meters of the station', en), `within 150${nb}meters of the station`);
    assert.equal(withNoBreakSpaces('« 30 min » et « 1 h »', en), `« 30${nb}min » et « 1${nb}h »`);
    assert.equal(withNoBreakSpaces('until 2:59 PM', en), `until 2:59${nb}PM`);
    assert.equal(withNoBreakSpaces('1 heure, 45 minutes, 24 hours, 7 days', en), `1${nb}heure, 45${nb}minutes, 24${nb}hours, 7${nb}days`);
  });

  it('leaves a number before another word, and a unit that is the start of a longer word', () => {
    assert.equal(withNoBreakSpaces('ligne 7 du métro, 3 minutieux, 2 hommes, 4 mois', fr), 'ligne 7 du métro, 3 minutieux, 2 hommes, 4 mois');
    assert.equal(withNoBreakSpaces('Step 3 hourly', en), 'Step 3 hourly');
  });

  it('leaves a number in a code', () => {
    assert.equal(withNoBreakSpaces('Run `sleep 10 min` now', en), 'Run `sleep 10 min` now');
  });

  it('leaves the pages of a section for a desk as they are', () => {
    assert.equal(withNoBreakSpaces('wait 24 hours', rulesForPage('en/maintain/after-the-release')), 'wait 24 hours');
  });
});

describe('typographyFaults', () => {
  it('names the line, and gives the line as it should be', () => {
    assert.deepEqual(typographyFaults('Bon\nUn mot : deux', fr), [{ line: 2, text: 'Un mot : deux', fixed: `Un mot${nb}: deux` }]);
  });

  it('finds nothing in a good page', () => {
    assert.deepEqual(typographyFaults(`Un mot${nb}: deux\n`, fr), []);
  });
});

// The line with ⍽ at each space to change, around the first one: a no-break space looks like a plain space in a terminal.
function marked(text: string, fixed: string): string {
  const first = text.split('').findIndex((character, index) => character !== fixed[index]);
  const line = text.split('').map((character, index) => (character === fixed[index] ? character : '⍽')).join('');
  return line.slice(Math.max(0, first - 50), first + 50);
}

// Every page of the site, as it is committed.
const contentFolder = new URL('content/docs/', import.meta.url);
const pages = readdirSync(contentFolder, { recursive: true, encoding: 'utf8' })
  .map((path) => path.split('\\').join('/'))
  .filter((path) => /\.mdx?$/.test(path));

describe('the pages of the site', () => {
  for (const path of pages) {
    it(`${path} has a no-break space at every place of the rules`, () => {
      const source = readFileSync(new URL(path, contentFolder), 'utf8');
      const faults = typographyFaults(source, rulesForPage(path.replace(/\.mdx?$/, '')));
      assert.deepEqual(
        faults.map(({ line, text, fixed }) => `${path}:${line}: ${marked(text, fixed)}`),
        [],
        `Replace each plain space marked ⍽ by a no-break space (U+00A0): before », :, ; ? and ! and after « on a French page, between a number and its unit on a riders page.`,
      );
    });
  }
});

describe('splitAtWords', () => {
  it('puts Wi-Fi in a box that never breaks, and keeps the text around it', () => {
    const nodes = splitAtWords('Hors du Wi-Fi, voyez aussi Wi-Fi.');
    assert.deepEqual(
      nodes?.map((node) => node.children?.[0].value ?? node.value),
      ['Hors du ', 'Wi-Fi', ', voyez aussi ', 'Wi-Fi', '.'],
    );
    assert.deepEqual(nodes?.[1].properties, { className: [noBreakClass] });
  });

  it('gives nothing for a text without the word, and for a longer word that holds it', () => {
    assert.equal(splitAtWords('Rien ici'), undefined);
    assert.equal(splitAtWords('Le Wi-Fi-Direct'), undefined);
    assert.equal(splitAtWords('Le sans-Wi-Fi'), undefined);
  });

  it('finds the word at the start and at the end of a text', () => {
    assert.equal(splitAtWords('Wi-Fi')?.length, 1);
    assert.equal(splitAtWords('Wi-Fi ou 4G')?.length, 2);
  });
});

describe('noBreakWordsPlugin', () => {
  type Node = { type: string; tagName?: string; properties?: Record<string, unknown>; value?: string };

  function run(value: string, parents: Node[]) {
    const text: Node = { type: 'text', value };
    const chain = new Map<Node, Node>();
    [text, ...parents].forEach((child, index, all) => {
      if (all[index + 1]) chain.set(child, all[index + 1]);
    });
    let replaced: unknown;
    noBreakWordsPlugin.text(text, {
      parent: (child) => chain.get(child),
      replaceNode: (_node, nodes) => {
        replaced = nodes;
      },
    });
    return replaced;
  }

  it('replaces the text of a paragraph and of a heading', () => {
    assert.ok(run('Hors du Wi-Fi', [{ type: 'element', tagName: 'p' }]));
    assert.ok(run('Hors du Wi-Fi', [{ type: 'element', tagName: 'h2' }]));
  });

  it('leaves a code alone, and the text that it has already put in a box', () => {
    assert.equal(run('Wi-Fi', [{ type: 'element', tagName: 'code' }]), undefined);
    assert.equal(run('Wi-Fi', [{ type: 'element', tagName: 'code' }, { type: 'element', tagName: 'pre' }]), undefined);
    assert.equal(run('Wi-Fi', [{ type: 'element', tagName: 'span', properties: { className: [noBreakClass] } }]), undefined);
  });
});

describe('inPieces', () => {
  it('reads the pieces of a result as one text, and gives each piece back with its length', () => {
    const pieces = ['« ', 'Horaires', ' ', 'indisponibles', ' » et 3 ', 'minutes'];
    const changed = inPieces(pieces, (text) => withNoBreakSpacesInText(text, { highPunctuation: true, units: true }));
    assert.deepEqual(changed, [`«${nb}`, 'Horaires', ' ', 'indisponibles', `${nb}» et 3${nb}`, 'minutes']);
    assert.deepEqual(changed.map((piece) => piece.length), pieces.map((piece) => piece.length));
  });

  it('gives back no piece for no piece', () => {
    assert.deepEqual(inPieces([], (text) => text), []);
  });
});

describe('withNoBreakHyphens', () => {
  it('puts a non-breaking hyphen in Wi-Fi, and keeps the length of the text', () => {
    assert.equal(withNoBreakHyphens('hors du Wi-Fi.'), 'hors du Wi‑Fi.');
    assert.equal(withNoBreakHyphens('hors du Wi-Fi.').length, 'hors du Wi-Fi.'.length);
  });

  it('leaves any other hyphen', () => {
    assert.equal(withNoBreakHyphens('Saint-Paul, sans-Wi-Fi'), 'Saint-Paul, sans-Wi-Fi');
  });
});

describe('withNoBreakHyphensInToc', () => {
  it('keeps Wi-Fi on one line in the table of contents, at every depth', () => {
    const toc = [{ text: 'Hors du Wi-Fi', children: [{ text: 'Le Wi-Fi coupé', children: [] }] }];
    withNoBreakHyphensInToc(toc);
    assert.deepEqual(toc, [{ text: 'Hors du Wi‑Fi', children: [{ text: 'Le Wi‑Fi coupé', children: [] }] }]);
  });
});
