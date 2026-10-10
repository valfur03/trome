import {K, film} from './timing';
import {css, night, type Palette} from './palette';
import {useSvgId} from './svgId';

// The canvas of the store pictures, drawn in world x: a horizontal sweep of the field colours that changes at each
// change of line, dark at the top and lit behind the headline; the line stroke with its station dots; the soft band
// of light along the line; and the light trail of a train going forward.

export type Segment = {from: number; to: number; palette: Palette; dots: number[]};

const blend = 260 * K; // half the width of the colour change at a change of line
export const strokeWidth = 40 * K;
const dotRadius = 14 * K;

export const Field = ({segments, camera, glowY}: {segments: Segment[]; camera: number; glowY: number}) => {
  const id = useSvgId();
  const start = segments[0].from - film.width;
  const end = segments[segments.length - 1].to + film.width;
  const at = (x: number) => (x - start) / (end - start);
  const stops: {offset: number; colour: string}[] = [];
  segments.forEach((segment, i) => {
    const left = i === 0 ? start : segment.from + blend;
    const right = i === segments.length - 1 ? end : segment.to - blend;
    stops.push({offset: at(left), colour: css(segment.palette.field)}, {offset: at(right), colour: css(segment.palette.field)});
  });
  return (
    <g>
      <defs>
        <linearGradient id={id('field-sweep')} gradientUnits="userSpaceOnUse" x1={start} y1={0} x2={end} y2={0}>
          {stops.map((stop, i) => (
            <stop key={i} offset={stop.offset} stopColor={stop.colour} />
          ))}
        </linearGradient>
        <linearGradient id={id('field-shade')} gradientUnits="userSpaceOnUse" x1={0} y1={0} x2={0} y2={glowY}>
          <stop offset={0} stopColor={css(night, 0.8)} />
          <stop offset={0.35} stopColor={css(night, 0.5)} />
          <stop offset={1} stopColor={css(night, 0)} />
        </linearGradient>
        {segments.map((segment, i) => (
          <radialGradient key={i} id={id(`field-glow-${i}`)}>
            <stop offset={0} stopColor={css(segment.palette.glow, 0.85)} />
            <stop offset={0.45} stopColor={css(segment.palette.glow, 0.32)} />
            <stop offset={1} stopColor={css(segment.palette.glow, 0)} />
          </radialGradient>
        ))}
      </defs>
      <rect x={start} y={0} width={end - start} height={film.height} fill={`url(#${id('field-sweep')})`} />
      <rect x={camera} y={0} width={film.width} height={glowY} fill={`url(#${id('field-shade')})`} />
      {segments.map((segment, i) => (
        <circle
          key={i}
          cx={(segment.from + segment.to) / 2}
          cy={glowY}
          r={1250 * K}
          fill={`url(#${id(`field-glow-${i}`)})`}
          style={{mixBlendMode: 'screen'}}
        />
      ))}
    </g>
  );
};

export const LineDrawing = ({segments, y}: {segments: Segment[]; y: number}) => {
  const id = useSvgId();
  return (
    <g>
      <defs>
        {segments.map((segment, i) => (
          <radialGradient key={i} id={id(`line-band-${i}`)}>
            <stop offset={0} stopColor={css(segment.palette.glow, 0.45)} />
            <stop offset={1} stopColor={css(segment.palette.glow, 0)} />
          </radialGradient>
        ))}
      </defs>
      {segments.map((segment, i) => (
        <ellipse
          key={`band-${i}`}
          cx={(segment.from + segment.to) / 2}
          cy={y}
          rx={(segment.to - segment.from) / 2}
          ry={150 * K}
          fill={`url(#${id(`line-band-${i}`)})`}
          style={{mixBlendMode: 'screen'}}
        />
      ))}
      {segments.map((segment, i) => (
        <line key={`stroke-${i}`} x1={segment.from} y1={y} x2={segment.to} y2={y} stroke={css(segment.palette.stroke)} strokeWidth={strokeWidth} />
      ))}
      {segments.flatMap((segment, i) =>
        segment.dots.map((x) => <circle key={`dot-${i}-${x}`} cx={x} cy={y} r={dotRadius} fill="white" />),
      )}
    </g>
  );
};

// The light of a train going forward: a white trail on the stroke behind the train, and a small halo ahead of its nose.
export const Trail = ({nose, length, y, palette}: {nose: number; length: number; y: number; palette: Palette}) => {
  const id = useSvgId()('trail');
  const tail = nose - length;
  const from = tail - 520 * K;
  return (
    <g>
      <defs>
        <linearGradient id={`${id}-trail`} gradientUnits="userSpaceOnUse" x1={from} y1={0} x2={tail + 20} y2={0}>
          <stop offset={0} stopColor="white" stopOpacity={0} />
          <stop offset={1} stopColor="white" stopOpacity={0.85} />
        </linearGradient>
        <radialGradient id={`${id}-halo`}>
          <stop offset={0} stopColor="white" stopOpacity={0.9} />
          <stop offset={0.3} stopColor={css(palette.glow, 0.35)} />
          <stop offset={1} stopColor={css(palette.glow, 0)} />
        </radialGradient>
      </defs>
      <rect x={from} y={y - strokeWidth / 2} width={nose - from} height={strokeWidth} fill={`url(#${id}-trail)`} />
      <circle cx={nose + 10} cy={y} r={70 * K} fill={`url(#${id}-halo)`} />
    </g>
  );
};
