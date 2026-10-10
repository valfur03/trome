import {Img, staticFile} from 'remotion';
import {inter} from './fonts';
import {K, film} from './timing';
import {css, type RGB} from './palette';

// The real captures of the app that the docs show (full screen, 900 x 1956, from the shared Simulator), in the
// language of the film. make copies them into public/app/ (see the Makefile).
export type Lang = 'fr' | 'en';
export const capture = (name: 'metro' | 'rer' | 'fork', lang: Lang) => staticFile(`app/live-activity-${name}-${lang}.png`);
const captureSize = {width: 900, height: 1956} as const;

// The lock cut of the store pictures: the bottom of the lock screen (the card, the home bar), cut by the top edge
// of the film, at the width that a 1206 wide capture has on a 1320 wide picture.
const cutWidth = 1206 * K;
const cutScale = cutWidth / captureSize.width;
const rowsTop = 1120;
export const lockCut = {width: cutWidth, scale: cutScale, rowsTop, height: (captureSize.height - rowsTop) * cutScale} as const;

export const LockCut = ({layers}: {layers: {src: string; opacity: number}[]}) => {
  const left = (film.width - lockCut.width) / 2;
  const corner = 64 * K;
  return (
    <div
      style={{
        position: 'absolute',
        left,
        top: 0,
        width: lockCut.width,
        height: lockCut.height,
        overflow: 'hidden',
        borderBottomLeftRadius: corner,
        borderBottomRightRadius: corner,
        boxShadow: `0 ${24 * K}px ${90 * K}px rgba(0, 0, 0, 0.55)`,
      }}
    >
      {layers.map((layer, i) => (
        <Img
          key={i}
          src={layer.src}
          style={{
            position: 'absolute',
            left: 0,
            top: -lockCut.rowsTop * lockCut.scale,
            width: lockCut.width,
            opacity: layer.opacity,
          }}
        />
      ))}
    </div>
  );
};

// The headline of the store pictures: bold, centred, broken after the comma, the part after it in the accent colour.
export const Headline = ({lines, accent, centreY, opacity = 1}: {lines: readonly [string, string]; accent: RGB; centreY: number; opacity?: number}) => {
  // Smaller than the 132 of the pictures: the longest French line must fit the narrower film with a margin.
  const size = 76;
  const step = size * 1.08;
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        width: film.width,
        top: centreY - step,
        fontFamily: inter,
        fontWeight: 700,
        fontSize: size,
        lineHeight: `${step}px`,
        letterSpacing: -0.5,
        textAlign: 'center',
        color: 'white',
        opacity,
      }}
    >
      <div>{lines[0]}</div>
      <div style={{color: css(accent)}}>{lines[1]}</div>
    </div>
  );
};
