// Marks each inline code that may be too long for one line on a phone, so that src/styles/custom.css lets it wrap,
// and the page never gets wider than the screen.
// Every other inline code stays on one line, so a short path or a make command never breaks in the middle.
// CSS alone cannot tell them apart: it cannot measure a code.

// The narrowest column of the site at 375 px wide (a list inside a step of a guide) holds 30 characters of inline code,
// and a paragraph at 375 px wide holds 42.
export const shortInlineCodeLength = 30;
export const phoneLineLength = 42;

// A short code stays on one line, as text that never breaks.
// A code that fits a phone line moves to the next line whole, as an inline block, when it does not fit the end of a line.
// A longer code can never fit a phone line, so it wraps like text.
export type InlineCodeLength = 'short' | 'whole' | 'wraps';
export const wholeClass = 'whole';
export const wrapsClass = 'wraps';
export const unitClass = 'code-unit';

export function inlineCodeLength(text: string): InlineCodeLength {
  const length = [...text].length;
  if (length <= shortInlineCodeLength) return 'short';
  return length <= phoneLineLength ? 'whole' : 'wraps';
}

// The opening punctuation just before a code, and the closing punctuation just after it, with the narrow spaces of French.
const leadingPunctuation = /[([{«“‘"'][  ]?$/u;
const trailingPunctuation = /^[  ]?[.,;:!?)\]}»”’"']+/u;

// Splits the text before and after a code into the punctuation that stays with the code, and the rest.
export function punctuationAround(before: string, after: string) {
  const lead = before.match(leadingPunctuation)?.[0] ?? '';
  const trail = after.match(trailingPunctuation)?.[0] ?? '';
  return { before: before.slice(0, before.length - lead.length), lead, trail, after: after.slice(trail.length) };
}

// The part of a node and of the context of a Sätteri hast plugin that this plugin uses.
type Node = { type: string; tagName?: string; value?: string; properties?: Record<string, unknown>; children?: Node[] };
type Context = {
  parent(node: Node): Node | undefined;
  indexOf(node: Node): number | undefined;
  textContent(node: Node): string;
  setProperty(node: Node, key: string, value: unknown): void;
  replaceNode(node: Node, newNode: Node): void;
};

function isInCodeBlock(node: Node, ctx: Context): boolean {
  for (let parent = ctx.parent(node); parent; parent = ctx.parent(parent)) {
    if (parent.type === 'element' && parent.tagName === 'pre') return true;
  }
  return false;
}

function classesWith(node: Node, name: string): unknown[] {
  const classes = node.properties?.className;
  return [...(Array.isArray(classes) ? classes : []), name];
}

function addClass(node: Node, ctx: Context, name: string) {
  ctx.setProperty(node, 'className', classesWith(node, name));
}

const text = (value: string): Node => ({ type: 'text', value });

// A browser may break a line between an inline block and the punctuation next to it, so the comma after the code
// would start the next line: the code and the punctuation that touches it go in one span that never breaks.
function joinPunctuation(node: Node, ctx: Context, value: string): boolean {
  const siblings = ctx.parent(node)?.children ?? [];
  const index = ctx.indexOf(node) ?? -1;
  const previous = siblings[index - 1]?.type === 'text' ? siblings[index - 1] : undefined;
  const next = siblings[index + 1]?.type === 'text' ? siblings[index + 1] : undefined;
  const split = punctuationAround(previous?.value ?? '', next?.value ?? '');
  if (!split.lead && !split.trail) return false;
  if (previous && split.lead) ctx.setProperty(previous, 'value', split.before);
  if (next && split.trail) ctx.setProperty(next, 'value', split.after);
  const code: Node = {
    type: 'element',
    tagName: 'code',
    properties: { ...node.properties, className: classesWith(node, wholeClass) },
    children: [text(value)],
  };
  const children = [split.lead && text(split.lead), code, split.trail && text(split.trail)].filter(Boolean) as Node[];
  ctx.replaceNode(node, { type: 'element', tagName: 'span', properties: { className: [unitClass] }, children });
  return true;
}

// The hast plugin of the Markdown and MDX pages (astro.config.mjs). A code block is left alone: it scrolls on its own.
export const longInlineCode = {
  name: 'long-inline-code',
  element: [
    {
      filter: ['code'],
      visit(node: Node, ctx: Context) {
        const value = ctx.textContent(node);
        const length = inlineCodeLength(value);
        if (length === 'short' || isInCodeBlock(node, ctx)) return;
        if (length === 'wraps') return addClass(node, ctx, wrapsClass);
        if (!joinPunctuation(node, ctx, value)) addClass(node, ctx, wholeClass);
      },
    },
  ],
};
