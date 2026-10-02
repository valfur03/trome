import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { draftsWithoutNotice, pagesWithoutTwin } from './site-pages.ts';

const contentFolder = new URL('content/docs/', import.meta.url);
const sitePages = readdirSync(contentFolder, { recursive: true, encoding: 'utf8' })
  .map((path) => path.split('\\').join('/'))
  .filter((path) => /\.mdx?$/.test(path));

describe('pagesWithoutTwin', () => {
  it('accepts a page that exists in both languages', () => {
    assert.deepEqual(pagesWithoutTwin(['fr/support.mdx', 'en/support.mdx']), []);
  });

  it('finds a riders page in one language only', () => {
    assert.deepEqual(pagesWithoutTwin(['fr/support.mdx', 'fr/privacy.mdx', 'en/support.mdx']), ['fr/privacy.mdx']);
    assert.deepEqual(pagesWithoutTwin(['en/privacy.mdx']), ['en/privacy.mdx']);
  });

  it('accepts an English page of a section in English only', () => {
    assert.deepEqual(pagesWithoutTwin(['en/build/install-on-your-iphone.mdx']), []);
  });
});

describe('draftsWithoutNotice', () => {
  it('finds a page with a placeholder and no draft notice', () => {
    const pages = [
      { path: 'fr/privacy.mdx', text: 'Écrivez à <Placeholder>adresse de contact</Placeholder>.' },
      { path: 'en/privacy.mdx', text: '<DraftNotice />\nWrite to <Placeholder>contact address</Placeholder>.' },
      { path: 'en/whats-new.mdx', text: 'No version yet.' },
    ];
    assert.deepEqual(draftsWithoutNotice(pages), ['fr/privacy.mdx']);
  });
});

describe('the pages of the site', () => {
  it('has each riders page in French and in English', () => {
    assert.deepEqual(pagesWithoutTwin(sitePages), [], 'Write the page in the other language too, at the same path.');
  });

  it('shows the draft notice on each page that has a placeholder', () => {
    const pages = sitePages.map((path) => ({ path, text: readFileSync(new URL(path, contentFolder), 'utf8') }));
    assert.deepEqual(draftsWithoutNotice(pages), [], 'Add <DraftNotice /> at the top of the page.');
  });
});
