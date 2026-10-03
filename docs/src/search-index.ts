import type { AstroIntegration } from 'astro';
import { readdir, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pagefind from 'pagefind';

const frenchElision = /(?<!\p{L})(c|d|j|l|m|n|s|t|qu|jusqu|lorsqu|puisqu|quoiqu)’(?=\p{L})/giu;

export function htmlForSearchIndex(html: string): string {
  return html.replace(frenchElision, "$1'").replace(/<br\s*\/?>/gi, ' $&');
}

function assertNoErrors<T extends { errors: string[] }>(response: T): T {
  if (response.errors.length > 0) {
    throw new Error(`Pagefind failed: ${response.errors.join('; ')}`);
  }
  return response;
}

export function searchIndex(): AstroIntegration {
  return {
    name: 'search-index',
    hooks: {
      'astro:build:done': async ({ dir, logger }) => {
        const siteFolder = fileURLToPath(dir);
        const indexFolder = fileURLToPath(new URL('./pagefind/', dir));
        const htmlFiles = (await readdir(siteFolder, { recursive: true, encoding: 'utf8' })).filter((path) =>
          path.endsWith('.html'),
        );
        try {
          const { index } = assertNoErrors(await pagefind.createIndex());
          if (!index) {
            throw new Error('Pagefind created no index.');
          }
          for (const sourcePath of htmlFiles) {
            const html = await readFile(join(siteFolder, sourcePath), 'utf8');
            assertNoErrors(await index.addHTMLFile({ sourcePath, content: htmlForSearchIndex(html) }));
          }
          await rm(indexFolder, { recursive: true, force: true });
          assertNoErrors(await index.writeFiles({ outputPath: indexFolder }));
          logger.info(`Indexed ${htmlFiles.length} HTML files again, so that a search finds a word after l’, d’ or qu’, and the words around a line break.`);
        } finally {
          await pagefind.close();
        }
      },
    },
  };
}
