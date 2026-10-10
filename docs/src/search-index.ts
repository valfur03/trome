import type { AstroIntegration } from 'astro';
import { readFileSync } from 'node:fs';
import { access, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { findPackageJSON } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pagefind from 'pagefind';
import type { IndexFile, PagefindIndex } from 'pagefind';

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

const entryFile = 'pagefind-entry.json';

export function entryOf(files: IndexFile[]): PagefindEntry {
  const entry = files.find(({ path }) => path === entryFile);
  if (!entry) {
    throw new Error(`Pagefind gave no ${entryFile} in its files.`);
  }
  return JSON.parse(new TextDecoder().decode(entry.content)) as PagefindEntry;
}

// Each file is on disk when its promise resolves, so the folder is complete when this one does.
export async function writeIndexFiles(indexFolder: string, files: IndexFile[]): Promise<void> {
  await rm(indexFolder, { recursive: true, force: true });
  for (const { path, content } of files) {
    const target = join(indexFolder, path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, content);
  }
}

function starlightPagefindVersion(): string {
  const starlightPackage = findPackageJSON('@astrojs/starlight', import.meta.url);
  const pagefindPackage = starlightPackage && findPackageJSON('pagefind', starlightPackage);
  if (!pagefindPackage) {
    throw new Error('Found no Pagefind package for Starlight in node_modules: run make docs-install.');
  }
  return (JSON.parse(readFileSync(pagefindPackage, 'utf8')) as { version: string }).version;
}

async function newIndex(): Promise<PagefindIndex> {
  const { index } = assertNoErrors(await pagefind.createIndex());
  if (!index) {
    throw new Error('Pagefind created no index.');
  }
  return index;
}

async function filesOf(index: PagefindIndex): Promise<IndexFile[]> {
  return assertNoErrors(await index.getFiles()).files;
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
        await access(join(indexFolder, entryFile)).catch((cause: unknown) => {
          throw new Error(
            'Found no search index of Starlight: put searchIndex() after starlight() in astro.config.mjs, and keep the search of Starlight on.',
            { cause },
          );
        });
        // Pagefind 1.5.2 answers before its files are on disk, and Starlight stops Pagefind at once, so a file of the index of Starlight can stay empty or short:
        // https://github.com/Pagefind/pagefind/issues/1271
        // So this hook never reads a file that Pagefind wrote, and never lets Pagefind write one: it takes the files in memory and writes them itself.
        // To compare with the index of Starlight, it builds that index again in memory, with the same call as Starlight.
        // A unit test checks that this copy is still the call of Starlight.
        // When a release of Pagefind fixes issue 1271, read pagefind-entry.json of Starlight again and remove this copy.
        try {
          const starlightIndex = await newIndex();
          assertNoErrors(await starlightIndex.addDirectory({ path: siteFolder }));
          const starlightEntry = { ...entryOf(await filesOf(starlightIndex)), version: starlightPagefindVersion() };
          const index = await newIndex();
          for (const sourcePath of htmlFiles) {
            const html = await readFile(join(siteFolder, sourcePath), 'utf8');
            assertNoErrors(await index.addHTMLFile({ sourcePath, content: htmlForSearchIndex(html) }));
          }
          const files = await filesOf(index);
          const differences = differencesFromStarlightIndex(starlightEntry, entryOf(files));
          if (differences.length > 0) {
            throw new Error(
              `The search index is not in step with the one of Starlight: ${differences.join('; ')}. See the search part of docs/README.md.`,
            );
          }
          await writeIndexFiles(indexFolder, files);
          logger.info(`Indexed ${htmlFiles.length} HTML files again, so that a search finds a word after l’, d’ or qu’, and the words around a line break.`);
        } finally {
          await pagefind.close();
        }
      },
    },
  };
}
