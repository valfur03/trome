import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { i18nSchema } from '@astrojs/starlight/schema';

const starlightKeys = Object.keys(i18nSchema().shape);
const french: Record<string, string> = JSON.parse(readFileSync(new URL('./content/i18n/fr.json', import.meta.url), 'utf8'));

describe('the French interface texts', () => {
  it('give each text of the search dialog in French, because Starlight has none for it', () => {
    const missing = starlightKeys.filter((key) => key.startsWith('pagefind.') && !french[key]);
    assert.deepEqual(missing, []);
  });

  it('use only keys that Starlight knows', () => {
    assert.deepEqual(
      Object.keys(french).filter((key) => !starlightKeys.includes(key)),
      [],
    );
  });

  it('keep the parts that the search fills in', () => {
    for (const key of ['pagefind.zero_results', 'pagefind.many_results', 'pagefind.one_result', 'pagefind.searching']) {
      assert.match(french[key], /\[SEARCH_TERM\]/, key);
    }
    assert.match(french['pagefind.many_results'], /\[COUNT\]/);
    assert.match(french['pagefind.alt_search'], /\[DIFFERENT_TERM\]/);
  });
});
