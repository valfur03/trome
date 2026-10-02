// Rules on the pages of the site, which the test of this folder checks on every page.

// The sections of the site that are in English only, because their readers build or run the app.
// Every other page is for riders, so it has a French page and an English page at the same path.
export const englishOnlyFolders = ['build/'];

const languages = ['fr', 'en'];

// The pages that miss their twin in the other language, for paths such as "fr/support.mdx".
export function pagesWithoutTwin(paths: string[]): string[] {
  const pages = new Set(paths);
  return paths.filter((path) => {
    const [language, ...rest] = path.split('/');
    const page = rest.join('/');
    if (!languages.includes(language) || englishOnlyFolders.some((folder) => page.startsWith(folder))) {
      return false;
    }
    return languages.some((other) => other !== language && !pages.has(`${other}/${page}`));
  });
}

// The pages that show a placeholder but no draft notice, so that nobody puts them online by mistake.
export function draftsWithoutNotice(pages: { path: string; text: string }[]): string[] {
  return pages
    .filter(({ text }) => text.includes('<Placeholder') && !text.includes('<DraftNotice'))
    .map(({ path }) => path);
}
