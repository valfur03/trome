import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// The href of each <link> whose rel names an icon, as in <link rel="shortcut icon" href="/favicon.png">.
export function iconLinks(html: string): string[] {
  const links = html.match(/<link\b[^>]*>/gi) ?? [];
  return links
    .filter((link) => /\brel=["'][^"']*\bicon\b[^"']*["']/i.test(link))
    .map((link) => /\bhref=["']([^"']+)["']/i.exec(link)?.[1])
    .filter((href): href is string => href !== undefined);
}

// Each page of the built site whose icon is not a file of the site, as "<page>: <href>".
// A redirect page is skipped: the browser leaves it at once, for a page that has the icon.
// Why: with no icon file, the browser tab of every page shows a blank icon, and no other check sees it.
export function missingIcons(distFolder: string): string[] {
  const pages = readdirSync(distFolder, { recursive: true, encoding: 'utf8' }).filter((path) => path.endsWith('.html'));
  return pages.flatMap((page) => {
    const html = readFileSync(join(distFolder, page), 'utf8');
    if (/<meta\b[^>]*http-equiv=["']refresh["']/i.test(html)) {
      return [];
    }
    const hrefs = iconLinks(html);
    if (hrefs.length === 0) {
      return [`${page}: no icon`];
    }
    return hrefs
      .filter((href) => !href.startsWith('/') || !existsSync(join(distFolder, href.split(/[?#]/)[0])))
      .map((href) => `${page}: ${href}`);
  });
}
