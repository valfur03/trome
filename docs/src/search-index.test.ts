import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { findPackageJSON } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { differencesFromStarlightIndex, entryOf, htmlForSearchIndex, writeIndexFiles } from './search-index.ts';

describe('htmlForSearchIndex', () => {
  it('gives Pagefind a straight apostrophe after a French elision, so it also indexes the word after it', () => {
    assert.equal(
      htmlForSearchIndex('<p>L’activité sur l’écran, d’une station, qu’il, s’affiche, n’est, c’est, jusqu’à</p>'),
      "<p>L'activité sur l'écran, d'une station, qu'il, s'affiche, n'est, c'est, jusqu'à</p>",
    );
  });

  it('keeps the apostrophe of a word that is not an elision', () => {
    assert.equal(
      htmlForSearchIndex('<p>the iPhone’s screen doesn’t show, aujourd’hui</p>'),
      '<p>the iPhone’s screen doesn’t show, aujourd’hui</p>',
    );
  });

  it('keeps an apostrophe that is not followed by a letter', () => {
    assert.equal(htmlForSearchIndex('<p>‘Live’ and l’ 2</p>'), '<p>‘Live’ and l’ 2</p>');
  });

  it('puts a space before a line break, so the words on both sides stay apart', () => {
    assert.equal(htmlForSearchIndex('<h1>Votre prochain métro,<br />sur l’écran</h1>'), "<h1>Votre prochain métro, <br />sur l'écran</h1>");
    assert.equal(htmlForSearchIndex('a<br>b<BR/>c'), 'a <br>b <BR/>c');
  });
});

describe('differencesFromStarlightIndex', () => {
  const starlight = { version: '1.5.2', languages: { en: { page_count: 5 }, fr: { page_count: 4 } } };

  it('finds no difference when the version and the pages of each language are the same', () => {
    assert.deepEqual(differencesFromStarlightIndex(starlight, structuredClone(starlight)), []);
  });

  it('names a different version of Pagefind, a language with other pages, and a missing language', () => {
    assert.deepEqual(
      differencesFromStarlightIndex(starlight, { version: '1.6.0', languages: { fr: { page_count: 3 } } }),
      [
        'Pagefind 1.6.0 built this index, but Starlight uses Pagefind 1.5.2: run npm install --save-exact pagefind@1.5.2 in docs/',
        '0 pages in "en", but 5 in the index of Starlight',
        '3 pages in "fr", but 4 in the index of Starlight',
      ],
    );
  });
});

describe('entryOf', () => {
  const file = (path: string, text: string) => ({ path, content: new TextEncoder().encode(text) });

  it('reads the entry of the index from the files in memory', () => {
    const entry = { version: '1.5.2', languages: { fr: { page_count: 4 } } };
    assert.deepEqual(entryOf([file('pagefind.js', ''), file('pagefind-entry.json', JSON.stringify(entry))]), entry);
  });

  it('says which file is missing', () => {
    assert.throws(() => entryOf([file('pagefind.js', '')]), /no pagefind-entry\.json/);
  });
});

describe('writeIndexFiles', () => {
  it('replaces the folder with the files, whole, in their subfolders', async () => {
    const folder = await mkdtemp(join(tmpdir(), 'search-index-test-'));
    try {
      const indexFolder = join(folder, 'pagefind');
      await writeIndexFiles(indexFolder, [{ path: 'old.js', content: new Uint8Array([1]) }]);
      const big = new Uint8Array(300_000).fill(7);
      await writeIndexFiles(indexFolder, [
        { path: 'pagefind-entry.json', content: new TextEncoder().encode('{}') },
        { path: 'fragment/fr_1.pf_fragment', content: big },
      ]);
      assert.deepEqual((await readdir(indexFolder, { recursive: true })).sort(), ['fragment', 'fragment/fr_1.pf_fragment', 'pagefind-entry.json']);
      assert.deepEqual(new Uint8Array(await readFile(join(indexFolder, 'fragment/fr_1.pf_fragment'))), big);
      assert.equal(await readFile(join(indexFolder, 'pagefind-entry.json'), 'utf8'), '{}');
    } finally {
      await rm(folder, { recursive: true, force: true });
    }
  });
});

describe('the copy of the Pagefind call of Starlight', () => {
  it('is still the call of Starlight, so the pages of its index are the pages that src/search-index.ts compares with', async () => {
    const starlightPackage = findPackageJSON('@astrojs/starlight', import.meta.url);
    assert.ok(starlightPackage, 'Found no Starlight package in node_modules: run make docs-install.');
    const source = await readFile(join(dirname(starlightPackage), 'dist/integrations/pagefind.js'), 'utf8');
    assert.match(source, /pagefind\.createIndex\(\)/, 'Starlight now gives options to createIndex: give the same ones in src/search-index.ts.');
    assert.match(
      source,
      /index\.addDirectory\(\{ path: fileURLToPath\(dir\) \}\)/,
      'Starlight now gives other options to addDirectory: give the same ones in src/search-index.ts.',
    );
  });
});
