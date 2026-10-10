import {useId} from 'react';

// An id of its own for each SVG gradient, pattern or clip, so two scenes on one page (the storyboard) never share one.
export function useSvgId(): (name: string) => string {
  const base = useId().replace(/[^a-zA-Z0-9]/g, '');
  return (name) => `${name}-${base}`;
}
