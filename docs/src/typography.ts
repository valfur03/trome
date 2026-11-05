// The spaces of a page that a line must never break at: French high punctuation and guillemets, a number and its unit.
// The source of a page holds the no-break space itself (U+00A0), so the page, its title, its alt texts and its search results all keep it.
// The test of this file reads every page, so a new page cannot bring a line that starts with », :, ;, ? or ! back.

import { isInBothLanguages } from './site-pages.ts';

export const noBreakSpace = '\u00A0';

// The rules that hold for a page, by its id ('fr/support', as in src/site-pages.ts).
// The high punctuation is French typography, so it holds for every French page.
// A number and its unit hold for the riders' pages, which a rider reads on a phone, in both languages;
// the pages of a section in English only (build, maintain) are read at a desk and keep their lines as the maintainer writes them.
export interface Rules {
  highPunctuation: boolean;
  units: boolean;
}

export function rulesForPage(id: string): Rules {
  return { highPunctuation: id.startsWith('fr/'), units: isInBothLanguages(id) };
}

// French typography: a space before », :, ;, ? and ! and after «, and a line may break at none of them.
// A space that starts a line (an indented block) is not before a word, so it stays.
const beforeHighPunctuation = /(?<=\S) (?=[»:;?!])/g;
const afterOpeningGuillemet = /(?<=«) (?=\S)/g;

// A number and its unit: '150' then 'mètres' on two lines reads as two numbers.
const units = [
  'min',
  'minutes?',
  'h',
  'heures?',
  'hours?',
  'secondes?',
  'seconds?',
  'jours?',
  'days?',
  'mètres?',
  'metres?',
  'meters?',
  'octets',
  'bytes?',
  'caractères',
  'characters',
  'Mo',
  'MB',
];
const beforeUnit = new RegExp(`(?<=\\d) (?=(?:${units.join('|')})(?![\\p{L}\\d]))`, 'gu');
const beforeDayPeriod = /(?<=\d) (?=[AP]M\b)/g;

export function withNoBreakSpacesInText(text: string, rules: Rules): string {
  let result = text;
  if (rules.units) result = result.replace(beforeUnit, noBreakSpace).replace(beforeDayPeriod, noBreakSpace);
  if (rules.highPunctuation) {
    result = result.replace(beforeHighPunctuation, noBreakSpace).replace(afterOpeningGuillemet, noBreakSpace);
  }
  return result;
}

// The pieces of one text, as the text nodes of a search result that a <mark> cuts: the rules read the text whole, and each piece keeps its length.
// Pagefind gives a result excerpt with plain spaces, so src/components/Header.astro puts them back in the page of the reader.
export function inPieces(pieces: string[], change: (text: string) => string): string[] {
  const changed = change(pieces.join(''));
  let start = 0;
  return pieces.map((piece) => {
    const result = changed.slice(start, start + piece.length);
    start += piece.length;
    return result;
  });
}

// An inline code is a command or a name that the reader copies: its spaces stay as they are.
// Each of its characters is hidden from the rules by one that no rule reads, so that a space after the code still has a character before it.
// A rule only changes a space into another character, so the line keeps its length and each place of a code is put back.
const inlineCode = /(`+)(?:(?!\1).)+?\1(?!`)/g;
const hidden = '\uE000';

function withNoBreakSpacesInLine(line: string, rules: Rules): string {
  const masked = line.replace(inlineCode, (code) => hidden.repeat(code.length));
  const changed = withNoBreakSpacesInText(masked, rules);
  return line.split('').map((character, index) => (masked[index] === hidden ? character : changed[index])).join('');
}

// The source of a Markdown or MDX page with a no-break space at each place of the rules above.
// A code block, an inline code and the import lines of an MDX page are left as they are.
export function withNoBreakSpaces(source: string, rules: Rules): string {
  let fence: string | undefined;
  return source
    .split('\n')
    .map((line) => {
      const marker = /^\s*(```+|~~~+)/.exec(line)?.[1];
      if (fence) {
        if (marker && marker[0] === fence[0] && marker.length >= fence.length) fence = undefined;
        return line;
      }
      if (marker) {
        fence = marker;
        return line;
      }
      if (/^(import|export)\s/.test(line)) return line;
      return withNoBreakSpacesInLine(line, rules);
    })
    .join('\n');
}

export interface Fault {
  line: number;
  text: string;
  fixed: string;
}

// The lines of a page that have a plain space where a no-break space belongs.
export function typographyFaults(source: string, rules: Rules): Fault[] {
  const fixed = withNoBreakSpaces(source, rules).split('\n');
  return source
    .split('\n')
    .flatMap((text, index) => (text === fixed[index] ? [] : [{ line: index + 1, text, fixed: fixed[index] }]));
}
