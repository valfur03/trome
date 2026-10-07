import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { contactEmail } from './contact.ts';
import { draftsWithoutNotice, isInBothLanguages, pagesWithoutTwin } from './site-pages.ts';

const contentFolder = new URL('content/docs/', import.meta.url);
const sitePages = readdirSync(contentFolder, { recursive: true, encoding: 'utf8' })
  .map((path) => path.split('\\').join('/'))
  .filter((path) => /\.mdx?$/.test(path));

describe('isInBothLanguages', () => {
  it('accepts a riders page and a home', () => {
    assert.equal(isInBothLanguages('fr/support'), true);
    assert.equal(isInBothLanguages('en'), true);
  });

  it('refuses a page of a section in English only, and a page outside the language folders', () => {
    assert.equal(isInBothLanguages('en/build/install-on-your-iphone'), false);
    assert.equal(isInBothLanguages('en/maintain/release-on-the-app-store'), false);
    assert.equal(isInBothLanguages('404'), false);
  });
});

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
    assert.deepEqual(pagesWithoutTwin(['en/maintain/release-on-the-app-store.mdx']), []);
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

  it('finds a page with a part to check and no draft notice', () => {
    const pages = [
      { path: 'fr/support.mdx', text: '<Unverified>Le message n’existe pas encore.</Unverified>' },
      { path: 'en/support.mdx', text: '<DraftNotice />\n<Unverified>The message does not exist yet.</Unverified>' },
    ];
    assert.deepEqual(draftsWithoutNotice(pages), ['fr/support.mdx']);
  });
});

describe('the pages of the site', () => {
  it('has each riders page in French and in English', () => {
    assert.deepEqual(pagesWithoutTwin(sitePages), [], 'Write the page in the other language too, at the same path.');
  });

  it('shows the draft notice on each page that has a placeholder or a part to check', () => {
    const pages = sitePages.map((path) => ({ path, text: readFileSync(new URL(path, contentFolder), 'utf8') }));
    assert.deepEqual(draftsWithoutNotice(pages), [], 'Add <DraftNotice /> at the top of the page.');
  });

  it('writes the contact address nowhere but in src/contact.ts', () => {
    const address = new RegExp(contactEmail.replace(/[.]/g, '\\.'), 'i');
    const pages = sitePages.filter((path) => address.test(readFileSync(new URL(path, contentFolder), 'utf8')));
    assert.deepEqual(pages, [], 'Show the address with <Contact />, so that a change of address is a change of src/contact.ts.');
  });
});
