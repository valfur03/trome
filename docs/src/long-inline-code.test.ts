import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { longInlineCode, shortInlineCodeLength, wrapsClass, wrapsOnAPhone } from './long-inline-code.ts';

// A page is wider than a phone when one inline code is too long to wrap; a short path or make command must not break.

describe('wrapsOnAPhone', () => {
  it('keeps a short path and a make command on one line', () => {
    assert.equal(wrapsOnAPhone('ios/Config/Secrets.xcconfig'), false);
    assert.equal(wrapsOnAPhone('make docs PORT=4545'), false);
  });

  it('lets a code wrap from one character past the limit', () => {
    assert.equal(wrapsOnAPhone('a'.repeat(shortInlineCodeLength)), false);
    assert.equal(wrapsOnAPhone('a'.repeat(shortInlineCodeLength + 1)), true);
  });

  it('lets a longer setting or a whole message wrap, as a numbered step at 375 px holds only 31 characters', () => {
    assert.equal(wrapsOnAPhone('TROME_BUNDLE_ID_PREFIX = com.example'), true);
    assert.equal(wrapsOnAPhone('FAILED: the Debug ID of the extension does not start with the Debug ID of the app'), true);
  });

  it('counts characters, not bytes', () => {
    assert.equal(wrapsOnAPhone('é'.repeat(shortInlineCodeLength)), false);
  });
});

type Node = { type: string; tagName?: string; properties?: Record<string, unknown>; text?: string };

// Runs the plugin on one code, with a context that changes the node in place, as Sätteri does for an element.
function visit(node: Node, parents: Node[]) {
  const chain = new Map<Node, Node>();
  [node, ...parents].forEach((child, index, all) => {
    if (all[index + 1]) chain.set(child, all[index + 1]);
  });
  longInlineCode.element[0].visit(node, {
    parent: (child) => chain.get(child),
    textContent: (child: Node) => child.text ?? '',
    setProperty: (child, key, value) => {
      child.properties = { ...child.properties, [key]: value };
    },
  });
  return node.properties?.className;
}

const paragraph: Node = { type: 'element', tagName: 'p' };
const long = 'TROME_BUNDLE_ID_PREFIX = com.example';

describe('longInlineCode', () => {
  it('marks a long inline code, and keeps its other classes', () => {
    const code = { type: 'element', tagName: 'code', text: long, properties: { className: ['other'] } };
    assert.deepEqual(visit(code, [paragraph]), ['other', wrapsClass]);
  });

  it('leaves a short inline code alone', () => {
    assert.equal(visit({ type: 'element', tagName: 'code', text: 'make check' }, [paragraph]), undefined);
  });

  it('leaves a code block alone: it scrolls on its own', () => {
    const pre = { type: 'element', tagName: 'pre' };
    const div = { type: 'element', tagName: 'div' };
    assert.equal(visit({ type: 'element', tagName: 'code', text: long }, [div, pre]), undefined);
  });
});
