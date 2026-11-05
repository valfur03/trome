// Marks each inline code that may be too long for a line on a phone, so that src/styles/custom.css lets it wrap like text,
// and the page never gets wider than the screen.
// Every other inline code stays on one line, so a short path or a make command never breaks in the middle.
// CSS alone cannot tell them apart: it cannot measure a code.

// The narrowest column of the site at 375 px wide (a list inside a numbered step of a guide) holds 31 characters of inline code,
// so a code of up to 30 characters always fits on one line, and a longer one may not.
// A longer code that would fit a wider column still wraps like text: shown as a box that moves to the next line whole,
// it would be split inside a box as wide as the column wherever the column is narrower than the code.
export const shortInlineCodeLength = 30;
export const wrapsClass = 'wraps';

export function wrapsOnAPhone(text: string): boolean {
  return [...text].length > shortInlineCodeLength;
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
        if (!wrapsOnAPhone(ctx.textContent(node)) || isInCodeBlock(node, ctx)) return;
        const classes = node.properties?.className;
        ctx.setProperty(node, 'className', [...(Array.isArray(classes) ? classes : []), wrapsClass]);
      },
    },
  ],
};
