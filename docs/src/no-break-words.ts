// Keeps a word with a hyphen on one line: 'Wi-Fi' broke into 'Wi-' and 'Fi' on a phone, and the reader reads two words; 'Île-de-France' ended a line with 'Île-de-'.
// A non-breaking hyphen (U+2011) in the page would change the word for the search and for a copy, and some fonts draw it from another font,
// so the page keeps its plain hyphen, and the word goes in a box that never breaks: src/styles/custom.css sets the class.

export const noBreakClass = 'nobreak';
export const noBreakWords = ['Wi-Fi', 'Île-de-France'];

const wordPattern = new RegExp(`(?<![\\p{L}\\d-])(?:${noBreakWords.join('|')})(?![\\p{L}\\d-])`, 'gu');

// The part of a node and of the context of a Sätteri hast plugin that this plugin uses.
type Node = { type: string; tagName?: string; properties?: Record<string, unknown>; value?: string };
type NewNode = Node & { children?: NewNode[] };
type Context = {
  parent(node: Node): Node | undefined;
  replaceNode(node: Node, replacement: NewNode[]): void;
};

// The nodes of a text, with each word in its own span; nothing when the text holds no such word.
export function splitAtWords(text: string): NewNode[] | undefined {
  const nodes: NewNode[] = [];
  let end = 0;
  for (const word of text.matchAll(wordPattern)) {
    if (word.index > end) nodes.push({ type: 'text', value: text.slice(end, word.index) });
    nodes.push({
      type: 'element',
      tagName: 'span',
      properties: { className: [noBreakClass] },
      children: [{ type: 'text', value: word[0] }],
    });
    end = word.index + word[0].length;
  }
  if (nodes.length === 0) return undefined;
  if (end < text.length) nodes.push({ type: 'text', value: text.slice(end) });
  return nodes;
}

// The HTML of a text with each such word in a box that never breaks, for a text that Starlight writes as HTML outside the Markdown (the tagline of a home).
export function withNoBreakBoxes(html: string): string {
  return html.replace(wordPattern, (word) => `<span class="${noBreakClass}">${word}</span>`);
}

// The text with a non-breaking hyphen (U+2011) inside each such word, and the same length.
// For a result of the search and the table of contents only, which the reader never copies and for which a box is too much: the page itself keeps its plain hyphen.
export function withNoBreakHyphens(text: string): string {
  return text.replace(wordPattern, (word) => word.replaceAll('-', '\u2011'));
}

// The table of contents of a page, with a non-breaking hyphen in each such word of its headings.
// Starlight writes it from the heading texts, outside the Markdown, so the box of the page never reaches it,
// and the narrow column of 'On this page' broke 'Wi-Fi' at 360 px. It is not in the search index, and a reader never copies it.
export function withNoBreakHyphensInToc<Item extends { text: string; children: Item[] }>(items: Item[]): void {
  for (const item of items) {
    item.text = withNoBreakHyphens(item.text);
    withNoBreakHyphensInToc(item.children);
  }
}

function isInCode(node: Node, ctx: Context): boolean {
  for (let parent = ctx.parent(node); parent; parent = ctx.parent(parent)) {
    if (parent.type !== 'element') continue;
    if (parent.tagName === 'code' || parent.tagName === 'pre') return true;
    const classes = parent.properties?.className;
    if (Array.isArray(classes) && classes.includes(noBreakClass)) return true;
  }
  return false;
}

// The hast plugin of the Markdown and MDX pages (astro.config.mjs). A code is left alone: it holds a command or a name to copy.
export const noBreakWordsPlugin = {
  name: 'no-break-words',
  text(node: Node, ctx: Context) {
    const nodes = splitAtWords(node.value ?? '');
    if (!nodes || isInCode(node, ctx)) return;
    ctx.replaceNode(node, nodes);
  },
};
