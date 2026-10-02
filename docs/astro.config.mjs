import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import starlightLinksValidator from 'starlight-links-validator';

// The address of the site on GitHub Pages: https://valfur03.github.io/trome/.
// The App Store page and the app link to its pages, so the address must not change once they do.
// GitHub does not redirect the address of a project site when the repo gets a new name.
// If the name of the repo changes, change `base` here: make docs-check then lists each link of the pages that still starts with the old one.
const site = 'https://valfur03.github.io';
const base = '/trome';

export default defineConfig({
  site,
  base,
  // French is the language of most riders, so the address of the site opens the French home.
  redirects: { '/': `${base}/fr/` },
  integrations: [
    starlight({
      title: 'TROME',
      description:
        'TROME montre les prochains métros et RER de la station la plus proche sur l’écran verrouillé de l’iPhone.',
      defaultLocale: 'fr',
      locales: {
        fr: { label: 'Français', lang: 'fr' },
        en: { label: 'English', lang: 'en' },
      },
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/valfur03/trome' }],
      customCss: ['./src/styles/custom.css'],
      plugins: [starlightLinksValidator()],
      routeMiddleware: './src/route-data.ts',
      sidebar: [
        {
          label: 'Utiliser TROME',
          translations: { en: 'Use TROME' },
          items: ['support', 'privacy', 'whats-new'],
        },
        {
          // In English only: src/route-data.ts hides it in the French sidebar, and the French home links to it.
          label: 'Build it yourself',
          items: [{ autogenerate: { directory: 'build' } }],
        },
      ],
    }),
  ],
});
