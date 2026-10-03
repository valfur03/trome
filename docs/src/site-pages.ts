// Rules on the pages of the site, which the test of this folder checks on every page.

// The sections of the site that are in English only, because their readers build or run the app.
// Every other page is for riders, so it has a French page and an English page at the same path.
export const englishOnlyFolders = ['build/'];

const languages = ['fr', 'en'];

export function isInBothLanguages(path: string): boolean {
  const [language, ...rest] = path.split('/');
  const page = rest.join('/');
  return languages.includes(language) && !englishOnlyFolders.some((folder) => page.startsWith(folder));
}

// The pages that miss their twin in the other language, for paths such as "fr/support.mdx".
export function pagesWithoutTwin(paths: string[]): string[] {
  const pages = new Set(paths);
  return paths.filter((path) => {
    if (!isInBothLanguages(path)) {
      return false;
    }
    const [language, ...rest] = path.split('/');
    const page = rest.join('/');
    return languages.some((other) => other !== language && !pages.has(`${other}/${page}`));
  });
}

// The components that mark a page as not ready: a fact still to fill in, or a part still to check.
const draftMarks = ['<Placeholder', '<Unverified'];

// The pages that show a draft mark but no draft notice, so that nobody puts them online by mistake.
export function draftsWithoutNotice(pages: { path: string; text: string }[]): string[] {
  return pages
    .filter(({ text }) => draftMarks.some((mark) => text.includes(mark)) && !text.includes('<DraftNotice'))
    .map(({ path }) => path);
}
