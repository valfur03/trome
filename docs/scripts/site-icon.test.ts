import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { iconLinks, missingIcons } from './site-icon.ts';

describe('iconLinks', () => {
  it('finds the icon links of a page, the Apple one included, and no other link', () => {
    const html =
      '<head><link rel="stylesheet" href="/a.css"><link rel="shortcut icon" href="/favicon.png" type="image/png"><link href="/apple.png" rel="apple-touch-icon"></head>';
    assert.deepEqual(iconLinks(html), ['/favicon.png', '/apple.png']);
    assert.deepEqual(iconLinks('<link rel="icon" href="/favicon.svg">'), ['/favicon.svg']);
    assert.deepEqual(iconLinks('<head></head>'), []);
  });
});

describe('missingIcons', () => {
  const page = (href: string) => `<html><head><link rel="shortcut icon" href="${href}"></head></html>`;

  it('accepts pages whose icon is a file of the site, and a redirect page with no icon', () => {
    const dist = mkdtempSync(join(tmpdir(), 'site-icon-'));
    try {
      mkdirSync(join(dist, 'fr'));
      writeFileSync(join(dist, 'favicon.png'), '');
      writeFileSync(join(dist, 'fr', 'index.html'), page('/favicon.png'));
      writeFileSync(join(dist, '404.html'), page('/favicon.png'));
      writeFileSync(join(dist, 'index.html'), '<head><meta http-equiv="refresh" content="0;url=/fr/"></head>');
      assert.deepEqual(missingIcons(dist), []);
    } finally {
      rmSync(dist, { recursive: true });
    }
  });

  it('finds a page whose icon is not there, and a page with no icon', () => {
    const dist = mkdtempSync(join(tmpdir(), 'site-icon-'));
    try {
      mkdirSync(join(dist, 'fr'));
      writeFileSync(join(dist, 'fr', 'index.html'), page('/favicon.svg'));
      writeFileSync(join(dist, '404.html'), '<html><head></head></html>');
      assert.deepEqual(missingIcons(dist).sort(), ['404.html: no icon', 'fr/index.html: /favicon.svg']);
    } finally {
      rmSync(dist, { recursive: true });
    }
  });
});
