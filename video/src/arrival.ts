// The storyboard of the arrival: the beats of the film, in order, with their times on one tempo grid, the capture
// that each one shows, its word on screen (most have none), and what moves in it.
// Plain TypeScript with no JSX, so that the scripts of the folder read the same list (scripts/name-stills.ts).

export type Lang = 'fr' | 'en';
export type Look = 'a' | 'b';

// 120 beats a minute: a beat every half second, a bar of four beats every 2 seconds. Every cut sits on a beat.
export const tempo = {bpm: 120, beatSeconds: 0.5} as const;

// The lines of the montage, with the colour of the app's transport data (stations.json of the app).
export const lineColours = {
  '1': 0xffbe00,
  '3': 0x6e6e00,
  '4': 0xa0006e,
  '6': 0x82dc73,
  '7': 0xff82b4,
  B: 0x5091cb,
} as const;
export type LineName = keyof typeof lineColours;

export type Beat = {
  id: string;
  from: number;
  to: number;
  // The capture of the lock screen (make film-captures), or none for the end card.
  capture?: 'parmentier' | 'strasbourg' | 'pont-neuf' | 'luxembourg' | 'corvisart';
  line: LineName;
  word?: Record<Lang, string>;
  moves: string;
};

export const beats: readonly Beat[] = [
  {
    id: '1-light',
    from: 0,
    to: 5,
    capture: 'parmentier',
    line: '3',
    moves: 'The phone, cut in half by the bottom edge, is dark for 4 beats; its screen lights on beat 5 (9:41); it starts to rise.',
  },
  {
    id: '2-already',
    from: 5,
    to: 9,
    capture: 'parmentier',
    line: '3',
    word: {fr: 'Déjà là.', en: 'Already there.'},
    moves: 'The phone rises, still cut, until the card of line 3 is in the light; the word comes on the downbeat at 7 s.',
  },
  {
    id: '3-hub',
    from: 9,
    to: 12,
    capture: 'strasbourg',
    line: '4',
    moves: 'Cut on the bar: another place (4, 8, 9, the card shows "+2"); the phone comes from the other edge, the light turns to line 4.',
  },
  {
    id: '4-fork',
    from: 12,
    to: 14,
    capture: 'pont-neuf',
    line: '7',
    moves: 'Cut on the bar: line 7 and its two branches; the phone slides on, the light turns pink.',
  },
  {
    id: '5-rer',
    from: 14,
    to: 16,
    capture: 'luxembourg',
    line: 'B',
    moves: 'Cut on the bar: an RER, its rows of times; the phone slides on, the light turns blue.',
  },
  {
    id: '6-every',
    from: 16,
    to: 21,
    capture: 'corvisart',
    line: '6',
    word: {fr: 'À chaque station.', en: 'At every station.'},
    moves: 'Cuts every 2 beats, then on every beat (Corvisart, Anvers, Abbesses, Liège, Goncourt, Saint-Paul, Pelleport, Cité Universitaire); the word holds over them.',
  },
  {
    id: '7-end',
    from: 21,
    to: 24,
    line: '1',
    moves: 'Cut on the bar: the icon and TROME, still; the light fades out on the last beat.',
  },
];

export const looks: readonly Look[] = ['a', 'b'];
export const languages: readonly Lang[] = ['fr', 'en'];

// The order of the frames of the Stills composition: each look, each language, each beat.
export const keyFrames = looks.flatMap((look) => languages.flatMap((lang) => beats.map((beat) => ({look, lang, beat}))));
export const keyFrameName = ({look, lang, beat}: (typeof keyFrames)[number]) => `${lang}-${look}-${beat.id}`;
