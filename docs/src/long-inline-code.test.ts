import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { isLongInlineCode, longInlineCode, longInlineCodeClass, longInlineCodeLength } from './long-inline-code.ts';

// A page is wider than a phone when one inline code is too long to wrap; a short path or make command must not break.

describe('isLongInlineCode', () => {
  it('keeps a short path and a make command on one line', () => {
    assert.equal(isLongInlineCode('ios/Config/Secrets.xcconfig'), false);
    assert.equal(isLongInlineCode('make docs PORT=4545'), false);
  });

  it('lets a code wrap from one character past the limit, counted in characters, not bytes', () => {
    assert.equal(isLongInlineCode('é'.repeat(longInlineCodeLength)), false);
    assert.equal(isLongInlineCode('a'.repeat(longInlineCodeLength + 1)), true);
  });

  it('lets a whole command or message wrap', () => {
    assert.equal(isLongInlineCode('FAILED: the Debug ID of the extension does not start with the Debug ID of the app'), true);
  });
});

type Node = { type: string; tagName?: string; properties?: Record<string, unknown>; text?: string };

function visit(node: Node, parents: Node[]) {
  const chain = new Map<Node, Node>();
  [node, ...parents].forEach((child, index, all) => {
    if (all[index + 1]) chain.set(child, all[index + 1]);
  });
  longInlineCode.element[0].visit(node, {
    parent: (child) => chain.get(child),
    textContent: (child) => child.text ?? '',
    setProperty: (child, key, value) => {
      child.properties = { ...child.properties, [key]: value };
    },
  });
  return node.properties?.className;
}

const paragraph: Node = { type: 'element', tagName: 'p' };
const long = 'git diff builds/1.0.0/4 builds/1.0.0/5 -- ios/Packages';

describe('longInlineCode', () => {
  it('marks a long inline code, and keeps its other classes', () => {
    const code = { type: 'element', tagName: 'code', text: long, properties: { className: ['other'] } };
    assert.deepEqual(visit(code, [paragraph]), ['other', longInlineCodeClass]);
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
