import { defineRouteMiddleware } from '@astrojs/starlight/route-data';
import { isInBothLanguages } from './site-pages.ts';

// A section in English only has no French page, so the French sidebar would show it as an empty group.
// This removes the empty groups, and the French home links to these sections instead.
// A page in English only also loses its hreflang links, which would point search engines at a French page that does not exist.
export const onRequest = defineRouteMiddleware(({ locals }) => {
  const route = locals.starlightRoute;
  route.sidebar = route.sidebar.filter((entry) => entry.type !== 'group' || entry.entries.length > 0);
  if (!isInBothLanguages(route.id)) {
    route.head = route.head.filter(({ tag, attrs }) => !(tag === 'link' && attrs?.rel === 'alternate' && attrs.hreflang));
  }
});
