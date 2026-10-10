import type {ReactNode} from 'react';
import {AbsoluteFill, Easing, interpolate} from 'remotion';
import {Field, LineDrawing, Trail, strokeWidth, type Segment} from './Canvas';
import {Headline, LockCut, capture, lockCut, type Lang} from './LockCut';
import {Tunnel, TunnelMouths} from './Tunnel';
import {Metro, Rer, metroLength, rerLength} from './Vehicles';
import {lines, palette} from './palette';
import {film} from './timing';

// The signature move of the film: a metro of line 1 runs along the stroke, goes into a tiled tunnel lit in the
// line colour, and comes out as an RER of line B; the card on the lock screen turns to line B at the same moment.
// Everything is a function of the time, so a still and the clip show the same frame.

export const text = {
  fr: ['Changez de ligne,', 'la carte suit.'],
  en: ['Change lines,', 'the card follows.'],
} as const;

const from = {line: lines.metro1, palette: palette(lines.metro1)};
const to = {line: lines.rerB, palette: palette(lines.rerB)};

const lineY = lockCut.height + 340;
export const layout = {lineY, headlineY: lineY + 300} as const;

// The world, in x: the tunnel is the change of line.
const tunnel = {x0: 1200, x1: 1800} as const;
const change = (tunnel.x0 + tunnel.x1) / 2;
const segments: Segment[] = [
  {from: -800, to: change, palette: from.palette, dots: [300, 650, 1000]},
  {from: change, to: 3600, palette: to.palette, dots: [2100, 2450, 2800, 3150]},
];

// The nose of the train: a steady speed from the first frame, then it slows down to stop at a station of line B.
const start = 380;
const stop = 2700;
const cruiseUntil = 4.9;
const brake = 1.4;
const speed = (stop - start) / (cruiseUntil + brake / 3);

export function noseAt(t: number): number {
  if (t <= cruiseUntil) return start + speed * t;
  const p = Math.min(1, (t - cruiseUntil) / brake);
  return start + speed * cruiseUntil + ((speed * brake) / 3) * Easing.out(Easing.cubic)(p);
}

// The time when the nose reaches a given x, during the steady part.
const timeAt = (x: number) => (x - start) / speed;
export const moments = {
  enters: timeAt(tunnel.x0),
  // The train changes when it is hidden: the metro is all inside, and the RER is not out yet.
  changes: timeAt(change + 200),
  exits: timeAt(tunnel.x1),
};

type SceneProps = {
  t: number;
  lang?: Lang;
  // A still of another beat draws the same line with its own headline, and what it adds over the card.
  headline?: readonly [string, string];
  overlay?: ReactNode;
};

export const SignatureScene = ({t, lang = 'fr', headline: words, overlay}: SceneProps) => {
  const nose = noseAt(t);
  const camera = Math.max(-40, nose - 0.62 * film.width);
  const changed = t >= moments.changes;
  const length = changed ? rerLength : metroLength;
  const current = changed ? to : from;
  const trainMiddle = nose - length / 2;
  const trainLight = interpolate(nose, [tunnel.x0 - 40, tunnel.x0 + 160, tunnel.x1 + 120, tunnel.x1 + length], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const spread = interpolate(t, [moments.changes, moments.changes + 0.7], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.quad),
  });
  const flash = interpolate(t, [moments.changes - 0.12, moments.changes, moments.changes + 0.45], [0, 0.85, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const cardTurn = interpolate(t, [moments.changes, moments.changes + 0.35], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const headline = interpolate(t, [0.1, 0.6], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const trainY = layout.lineY - strokeWidth / 2;
  const Vehicle = changed ? Rer : Metro;
  return (
    <AbsoluteFill>
      <svg width={film.width} height={film.height} style={{position: 'absolute'}}>
        <g transform={`translate(${-camera}, 0)`}>
          <Field segments={segments} camera={camera} glowY={layout.headlineY} />
          <LineDrawing segments={segments} y={layout.lineY} />
          <TunnelMouths x0={tunnel.x0} x1={tunnel.x1} lineY={layout.lineY} />
          <Trail nose={nose} length={length} y={layout.lineY} palette={current.palette} />
          <Vehicle palette={current.palette} x={nose} y={trainY} />
          <Tunnel
            x0={tunnel.x0}
            x1={tunnel.x1}
            lineY={layout.lineY}
            from={from}
            to={to}
            trainX={trainMiddle}
            trainLight={trainLight}
            change={spread}
            flash={flash}
          />
        </g>
      </svg>
      <LockCut
        layers={[
          {src: capture('metro', lang), opacity: 1},
          {src: capture('rer', lang), opacity: cardTurn},
        ]}
      />
      {overlay}
      <Headline
        lines={words ?? text[lang]}
        accent={(changed ? to : from).palette.accent}
        centreY={layout.headlineY}
        opacity={words ? 1 : headline}
      />
    </AbsoluteFill>
  );
};
