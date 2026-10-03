export type KnownWarning = {
  text: string;
  reason: string;
  upstream: string;
};

export const knownBuildWarnings: KnownWarning[] = [
  {
    text: 'The semantics of the module level directive "use astro:head-inject"',
    reason:
      'Astro 7.3.5 (also 7.4.0-beta.1) still writes a directive that it no longer reads into each MDX page, and Rolldown 1.2.9 and later warn about it, once for each page; the build is not affected.',
    upstream: 'https://github.com/withastro/astro/issues/18087',
  },
];
