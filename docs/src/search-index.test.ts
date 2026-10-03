import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { differencesFromStarlightIndex, htmlForSearchIndex } from './search-index.ts';

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
