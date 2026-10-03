import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      // A picture of the app beside the headline of a splash page, shown by src/components/Hero.astro with the Screenshot component.
      // Starlight's own `hero.image` would show it with the Image component, which the pictures of the app never use.
      extend: ({ image }) =>
        z.object({
          heroScreenshot: z
            .object({
              file: image(),
              alt: z.string(),
            })
            .optional(),
        }),
    }),
  }),
  i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
};
