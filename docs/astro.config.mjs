import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import starlightLinksValidator from 'starlight-links-validator';
import { searchIndex } from './src/search-index.ts';

// The address of the site: https://trome.valfur.fr/, at the root of its own domain, with no repo name in the path.
// The App Store page and the app link to its pages, and Apple keeps these addresses until a new version, so this address must not change once they do.
// It is a domain of its own so that it depends on neither the GitHub account nor the name of the repo.
// The domain itself is set in the repo settings, Pages: see "Publish the site" in docs/README.md.
const site = 'https://trome.valfur.fr';

export default defineConfig({
  site,
  // French is the language of most riders, so the address of the site opens the French home.
  redirects: { '/': '/fr/' },
  integrations: [
    starlight({
      title: 'TROME',
      description:
        'TROME montre les prochains métros et RER de la station la plus proche sur l’écran verrouillé de l’iPhone.',
      // The icon of the browser tab is the app icon, made smaller: ios/guide/assets.md says how to make it again.
      favicon: '/favicon.png',
      defaultLocale: 'fr',
      locales: {
        fr: { label: 'Français', lang: 'fr' },
        en: { label: 'English', lang: 'en' },
      },
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/valfur03/trome' }],
      customCss: ['./src/styles/custom.css'],
      plugins: [starlightLinksValidator()],
      routeMiddleware: './src/route-data.ts',
      disable404Route: true,
      components: {
        Header: './src/components/Header.astro',
        Hero: './src/components/Hero.astro',
        LanguageSelect: './src/components/LanguageSelect.astro',
      },
      sidebar: [
        {
          label: 'Utiliser TROME',
          translations: { en: 'Use TROME' },
          items: ['support', 'privacy', 'whats-new'],
        },
        {
          // In English only: src/route-data.ts hides it in the French sidebar, src/components/LanguageSelect.astro hides the language menu of its pages, and the French home links to it.
          label: 'Build it yourself',
          items: [{ autogenerate: { directory: 'build' } }],
        },
        {
          // In English only, like the section above, for the maintainer who releases the app; the homes do not link to it.
          label: 'Maintain',
          items: [{ autogenerate: { directory: 'maintain' } }],
        },
      ],
    }),
    searchIndex(),
  ],
});
