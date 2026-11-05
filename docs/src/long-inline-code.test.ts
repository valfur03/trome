import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  inlineCodeLength,
  longInlineCode,
  phoneLineLength,
  punctuationAround,
  shortInlineCodeLength,
  unitClass,
  wholeClass,
  wrapsClass,
} from './long-inline-code.ts';

// A page is wider than a phone when one inline code is too long to wrap; a short path or make command must not break,
// and the punctuation next to a long code must not start or end a line alone.

describe('inlineCodeLength', () => {
  it('keeps a short path and a make command on one line', () => {
    assert.equal(inlineCodeLength('ios/Config/Secrets.xcconfig'), 'short');
    assert.equal(inlineCodeLength('make docs PORT=4545'), 'short');
  });

  it('moves a longer make command to the next line whole, as long as it fits a phone line', () => {
    assert.equal(inlineCodeLength('make server-secret NAME=APP_TOKEN'), 'whole');
    assert.equal(inlineCodeLength('a'.repeat(phoneLineLength)), 'whole');
  });

  it('lets a whole command or message wrap like text', () => {
    assert.equal(inlineCodeLength('a'.repeat(phoneLineLength + 1)), 'wraps');
    assert.equal(inlineCodeLength('FAILED: the Debug ID of the extension does not start with the Debug ID of the app'), 'wraps');
  });

  it('counts characters, not bytes', () => {
    assert.equal(inlineCodeLength('é'.repeat(shortInlineCodeLength)), 'short');
    assert.equal(inlineCodeLength('é'.repeat(shortInlineCodeLength + 1)), 'whole');
  });
});

describe('punctuationAround', () => {
  it('keeps a comma, a full stop and brackets with the code', () => {
    assert.deepEqual(punctuationAround('In ', ', do the same'), { before: 'In ', lead: '', trail: ',', after: ' do the same' });
    assert.deepEqual(punctuationAround('that set (', '), make'), { before: 'that set ', lead: '(', trail: '),', after: ' make' });
    assert.deepEqual(punctuationAround('to ', '.'), { before: 'to ', lead: '', trail: '.', after: '' });
  });

  it('keeps French quotes and their narrow spaces with the code', () => {
    assert.deepEqual(punctuationAround('le texte « ', ' ».'), {
      before: 'le texte ',
      lead: '« ',
      trail: ' ».',
      after: '',
    });
  });

  it('leaves words and plain spaces where they are', () => {
    assert.deepEqual(punctuationAround('run ', ' and then'), { before: 'run ', lead: '', trail: '', after: ' and then' });
  });
});

type Node = { type: string; tagName?: string; value?: string; properties?: Record<string, unknown>; children?: Node[] };

const textNode = (value: string): Node => ({ type: 'text', value });
const code = (value: string, properties: Record<string, unknown> = {}): Node => ({
  type: 'element',
  tagName: 'code',
  properties,
  children: [textNode(value)],
});

// Runs the plugin on each code of a tree, with a context that changes the tree in place, as Sätteri does.
function run(root: Node): Node {
  const parents = new Map<Node, Node>();
  const codes: Node[] = [];
  const walk = (node: Node) => {
    for (const child of node.children ?? []) {
      parents.set(child, node);
      if (child.tagName === 'code') codes.push(child);
      walk(child);
    }
  };
  walk(root);
  for (const node of codes) {
    longInlineCode.element[0].visit(node, {
      parent: (child) => parents.get(child),
      indexOf: (child) => parents.get(child)?.children?.indexOf(child),
      textContent: (child) => (child.children ?? []).map((grandChild) => grandChild.value ?? '').join(''),
      // As in Sätteri: the property of an element is an attribute, the property of a text is the text node's own.
      setProperty: (child, key, value) =>
        child.type === 'element' ? (child.properties = { ...child.properties, [key]: value }) : Object.assign(child, { [key]: value }),
      replaceNode: (child, newNode) => {
        const siblings = parents.get(child)?.children ?? [];
        siblings[siblings.indexOf(child)] = newNode;
      },
    });
  }
  return root;
}

const paragraph = (...children: Node[]): Node => ({ type: 'root', children: [{ type: 'element', tagName: 'p', children }] });
const childrenOf = (root: Node) => root.children?.[0]?.children;
const fits = 'make server-secret NAME=APP_TOKEN';
const long = 'git diff builds/1.0.0/4 builds/1.0.0/5 -- ios/Packages';

describe('longInlineCode', () => {
  it('marks a code that fits a phone line, and keeps its other properties', () => {
    const root = run(paragraph(textNode('Run '), code(fits, { className: ['other'], dir: 'auto' }), textNode(' and wait')));
    assert.deepEqual(childrenOf(root), [
      textNode('Run '),
      code(fits, { className: ['other', wholeClass], dir: 'auto' }),
      textNode(' and wait'),
    ]);
  });

  it('puts the punctuation next to a code that fits a phone line in one unit with it', () => {
    const root = run(paragraph(textNode('the build ('), code(fits), textNode('), then')));
    assert.deepEqual(childrenOf(root), [
      textNode('the build '),
      {
        type: 'element',
        tagName: 'span',
        properties: { className: [unitClass] },
        children: [textNode('('), code(fits, { className: [wholeClass] }), textNode('),')],
      },
      textNode(' then'),
    ]);
  });

  it('marks a longer code to wrap like text, and leaves its punctuation as text', () => {
    const root = run(paragraph(textNode('that set ('), code(long), textNode('), make')));
    assert.deepEqual(childrenOf(root), [textNode('that set ('), code(long, { className: [wrapsClass] }), textNode('), make')]);
  });

  it('leaves a short inline code alone, with its comma', () => {
    const root = run(paragraph(textNode('Run '), code('make check'), textNode(', then')));
    assert.deepEqual(childrenOf(root), [textNode('Run '), code('make check'), textNode(', then')]);
  });

  it('leaves a code block alone: it scrolls on its own', () => {
    const root: Node = { type: 'root', children: [{ type: 'element', tagName: 'pre', children: [code(long)] }] };
    run(root);
    assert.deepEqual(root.children?.[0]?.children, [code(long)]);
  });
});
