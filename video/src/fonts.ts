import {loadFont} from '@remotion/fonts';
import interUrl from '@fontsource-variable/inter/files/inter-latin-wght-normal.woff2';

// Inter (SIL Open Font License 1.1) for every text that the film draws: never an Apple font, whose licence excludes it.
// The render waits until the font is loaded, so no frame shows a fallback font.
export const inter = 'Inter';

loadFont({family: inter, url: interUrl, weight: '100 900'});
