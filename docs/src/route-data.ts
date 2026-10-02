import { defineRouteMiddleware } from '@astrojs/starlight/route-data';

// A section in English only has no French page, so the French sidebar would show it as an empty group.
// This removes the empty groups, and the French home links to these sections instead.
export const onRequest = defineRouteMiddleware(({ locals }) => {
  const route = locals.starlightRoute;
  route.sidebar = route.sidebar.filter((entry) => entry.type !== 'group' || entry.entries.length > 0);
});
