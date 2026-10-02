import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import starlightLinksValidator from 'starlight-links-validator';

export default defineConfig({
  integrations: [
    starlight({
      title: 'TROME',
      description: 'Install, test and publish the TROME iPhone app.',
      customCss: ['./src/styles/custom.css'],
      plugins: [starlightLinksValidator()],
      sidebar: [
        { label: 'Home', link: '/' },
        { label: 'Tutorial', items: [{ autogenerate: { directory: 'tutorial' } }] },
      ],
    }),
  ],
});
