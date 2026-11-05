// Marks each inline code that may be too long for one line on a phone, so that src/styles/custom.css lets it wrap.
// Every other inline code stays inline and on one line, so a short path or a make command never breaks in the middle.
// CSS alone cannot tell them apart: it cannot measure a code.
// The long ones only are inline blocks, because the browser may put the comma or the full stop after an inline block
// at the start of the next line.

// The narrowest column of the site at 375 px wide (a list inside a step of a guide) holds 31 characters of inline code.
// A code of up to 30 characters therefore always fits, and a longer one may not.
export const longInlineCodeLength = 30;
export const longInlineCodeClass = 'long';

export function isLongInlineCode(text: string): boolean {
  return [...text].length > longInlineCodeLength;
}

// The part of a node and of the context of a Sätteri hast plugin that this plugin uses.
type Node = { type: string; tagName?: string; properties?: Record<string, unknown> };
type Context = {
  parent(node: Node): Node | undefined;
  textContent(node: Node): string;
  setProperty(node: Node, key: string, value: unknown): void;
};

function isInCodeBlock(node: Node, ctx: Context): boolean {
  for (let parent = ctx.parent(node); parent; parent = ctx.parent(parent)) {
    if (parent.type === 'element' && parent.tagName === 'pre') return true;
  }
  return false;
}

// The hast plugin of the Markdown and MDX pages (astro.config.mjs). A code block is left alone: it scrolls on its own.
export const longInlineCode = {
  name: 'long-inline-code',
  element: [
    {
      filter: ['code'],
      visit(node: Node, ctx: Context) {
        if (!isLongInlineCode(ctx.textContent(node)) || isInCodeBlock(node, ctx)) return;
        const classes = node.properties?.className;
        ctx.setProperty(node, 'className', [...(Array.isArray(classes) ? classes : []), longInlineCodeClass]);
      },
    },
  ],
};
