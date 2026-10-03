import type { AstroIntegration } from 'astro';
import { readdir, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pagefind from 'pagefind';

const frenchElision = /(?<!\p{L})(c|d|j|l|m|n|s|t|qu|jusqu|lorsqu|puisqu|quoiqu)’(?=\p{L})/giu;

export function htmlForSearchIndex(html: string): string {
  return html.replace(frenchElision, "$1'").replace(/<br\s*\/?>/gi, ' $&');
}

interface PagefindEntry {
  version: string;
  languages: Record<string, { page_count: number }>;
}

export function differencesFromStarlightIndex(starlight: PagefindEntry, ours: PagefindEntry): string[] {
  const differences: string[] = [];
  if (starlight.version !== ours.version) {
    differences.push(
      `Pagefind ${ours.version} built this index, but Starlight uses Pagefind ${starlight.version}: run npm install --save-exact pagefind@${starlight.version} in docs/`,
    );
  }
  const languages = new Set([...Object.keys(starlight.languages), ...Object.keys(ours.languages)]);
  for (const language of [...languages].sort()) {
    const starlightCount = starlight.languages[language]?.page_count ?? 0;
    const ourCount = ours.languages[language]?.page_count ?? 0;
    if (starlightCount !== ourCount) {
      differences.push(`${ourCount} pages in "${language}", but ${starlightCount} in the index of Starlight`);
    }
  }
  return differences;
}

async function readEntry(indexFolder: string): Promise<PagefindEntry> {
  return JSON.parse(await readFile(join(indexFolder, 'pagefind-entry.json'), 'utf8')) as PagefindEntry;
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
        const starlightEntry = await readEntry(indexFolder).catch((cause: unknown) => {
          throw new Error(
            'Found no search index of Starlight: put searchIndex() after starlight() in astro.config.mjs, and keep the search of Starlight on.',
            { cause },
          );
        });
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
          const differences = differencesFromStarlightIndex(starlightEntry, await readEntry(indexFolder));
          if (differences.length > 0) {
            throw new Error(
              `The search index is not in step with the one of Starlight: ${differences.join('; ')}. See the search part of docs/README.md.`,
            );
          }
          logger.info(`Indexed ${htmlFiles.length} HTML files again, so that a search finds a word after l’, d’ or qu’, and the words around a line break.`);
        } finally {
          await pagefind.close();
        }
      },
    },
  };
}
