import {Img, staticFile} from 'remotion';
import type {Beat, Lang} from './arrival';

// Apple's iPhone 18 Pro bezel, as it is (its licence forbids copies, so make copies it into public/app/ from the
// file of each maintainer), and the hole of its screen, which has the size of the Simulator's captures.
export const bezel = {width: 1350, height: 2760, screen: {x: 72, y: 69, width: 1206, height: 2622}} as const;

// Where the card of the Live Activity sits in a capture of the lock screen, in its pixels.
export const card = {top: 1812, bottom: 2235} as const;

export const captureOf = (name: NonNullable<Beat['capture']>, lang: Lang) => staticFile(`app/film/lock-${name}-${lang}.png`);

// The phone: a real capture of the lock screen, whole, under the bezel, scaled down only (never up, so no pixel
// is blurred), at whole pixels. Nothing is drawn on it: no shadow, no reflection, no tilt. With no capture, the
// screen is off (black), as a locked phone in the dark.
export const Phone = ({src, scale, centreX, top}: {src?: string; scale: number; centreX: number; top: number}) => {
  const width = Math.round(bezel.width * scale);
  const height = Math.round(bezel.height * scale);
  const screen = {
    left: bezel.screen.x * scale,
    top: bezel.screen.y * scale,
    width: bezel.screen.width * scale,
    height: bezel.screen.height * scale,
  };
  return (
    <div style={{position: 'absolute', left: Math.round(centreX - width / 2), top: Math.round(top), width, height}}>
      {src ? (
        <Img src={src} style={{position: 'absolute', ...screen}} />
      ) : (
        <div style={{position: 'absolute', ...screen, backgroundColor: 'black'}} />
      )}
      <Img src={staticFile('app/bezel.png')} style={{position: 'absolute', left: 0, top: 0, width, height}} />
    </div>
  );
};

// The y of the centre of the card, in the film, for a phone at this scale and top.
export const cardCentre = (scale: number, top: number) => top + (bezel.screen.y + (card.top + card.bottom) / 2) * scale;
