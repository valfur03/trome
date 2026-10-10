import {Badge} from './Badge';
import {css, mix, night, type Line, type Palette, type RGB} from './palette';
import {useSvgId} from './svgId';

// The tunnel of a change of line, seen from the side: a wall of the white bevelled tiles of the Paris stations,
// lit in the colour of the line. The train runs behind it. When the train reaches the middle, the light of the
// next line spreads from there to both ends, so the train comes out on the next line.

export const tile = {width: 34, height: 17} as const;

type Props = {
  x0: number;
  x1: number;
  lineY: number;
  from: {line: Line; palette: Palette};
  to: {line: Line; palette: Palette};
  // The middle of the train, in the same x as the tunnel, and how much of its light shows (0 to 1).
  trainX: number;
  trainLight: number;
  // How far the light of the next line has spread (0 to 1), and the white flash of the change (0 to 1).
  change: number;
  flash: number;
};

const top = (lineY: number) => lineY - 190;
const bottom = (lineY: number) => lineY + 46;

const tint = (colour: RGB) => css(mix([255, 255, 255], colour, 0.55));

export const Tunnel = ({x0, x1, lineY, from, to, trainX, trainLight, change, flash}: Props) => {
  const id = useSvgId();
  const y0 = top(lineY);
  const y1 = bottom(lineY);
  const width = x1 - x0;
  const height = y1 - y0;
  const middle = (x0 + x1) / 2;
  const outline = `M ${x0} ${y0 + 70} Q ${x0} ${y0} ${x0 + 70} ${y0} H ${x1 - 70} Q ${x1} ${y0} ${x1} ${y0 + 70} V ${y1 - 12} Q ${x1} ${y1} ${x1 - 12} ${y1} H ${x0 + 12} Q ${x0} ${y1} ${x0} ${y1 - 12} Z`;
  const light = mix(from.palette.glow, to.palette.glow, change > 0 ? 1 : 0);
  const reach = change * width * 0.75;
  const w = tile.width;
  const h = tile.height;
  return (
    <g>
      <defs>
        <pattern id={id('tile')} width={w} height={h} patternUnits="userSpaceOnUse" x={x0} y={y0}>
          <rect width={w} height={h} fill="#a9a499" />
          <rect x={1} y={1} width={w - 2} height={h - 2} rx={2} fill={`url(#${id('tile-face')})`} />
          <path d={`M 1 ${h - 1} V 1 H ${w - 1} L ${w - 4} 4 H 4 V ${h - 4} Z`} fill="white" opacity={0.9} />
          <path d={`M ${w - 1} 1 V ${h - 1} H 1 L 4 ${h - 4} H ${w - 4} V 4 Z`} fill="black" opacity={0.2} />
        </pattern>
        <linearGradient id={id('tile-face')} x1={0} y1={0} x2={0} y2={1}>
          <stop offset={0} stopColor="#fbfaf6" />
          <stop offset={1} stopColor="#e4e0d6" />
        </linearGradient>
        <clipPath id={id('tunnel-shape')}>
          <path d={outline} />
        </clipPath>
        <linearGradient id={id('tunnel-round')} x1={0} y1={0} x2={0} y2={1}>
          <stop offset={0} stopColor="#8f9199" />
          <stop offset={0.42} stopColor="#ffffff" />
          <stop offset={0.75} stopColor="#f4f4f4" />
          <stop offset={1} stopColor="#9a9ba2" />
        </linearGradient>
        <radialGradient id={id('tunnel-change')} cx={middle} cy={lineY - 60} r={Math.max(reach, 1)} gradientUnits="userSpaceOnUse">
          <stop offset={0} stopColor="white" />
          <stop offset={0.75} stopColor="white" />
          <stop offset={1} stopColor="black" />
        </radialGradient>
        <mask id={id('tunnel-change-mask')} maskUnits="userSpaceOnUse" x={x0} y={y0} width={width} height={height}>
          <rect x={x0} y={y0} width={width} height={height} fill={change > 0 ? `url(#${id('tunnel-change')})` : 'black'} />
        </mask>
        <radialGradient id={id('tunnel-before')} cx={middle} cy={lineY - 60} r={Math.max(reach, 1)} gradientUnits="userSpaceOnUse">
          <stop offset={0} stopColor="black" />
          <stop offset={0.75} stopColor="black" />
          <stop offset={1} stopColor="white" />
        </radialGradient>
        <mask id={id('tunnel-before-mask')} maskUnits="userSpaceOnUse" x={x0} y={y0} width={width} height={height}>
          <rect x={x0} y={y0} width={width} height={height} fill={change > 0 ? `url(#${id('tunnel-before')})` : 'white'} />
        </mask>
        <radialGradient id={id('tunnel-train-light')}>
          <stop offset={0} stopColor={css([255, 255, 255], 0.95)} />
          <stop offset={0.25} stopColor={css(light, 0.9)} />
          <stop offset={1} stopColor={css(light, 0)} />
        </radialGradient>
        <radialGradient id={id('tunnel-flash')}>
          <stop offset={0} stopColor={css([255, 255, 255], 0.95)} />
          <stop offset={1} stopColor={css([255, 255, 255], 0)} />
        </radialGradient>
        <linearGradient id={id('tunnel-portal')} x1={0} y1={0} x2={1} y2={0}>
          <stop offset={0} stopColor={css(night, 0.8)} />
          <stop offset={0.09} stopColor={css(night, 0)} />
          <stop offset={0.91} stopColor={css(night, 0)} />
          <stop offset={1} stopColor={css(night, 0.8)} />
        </linearGradient>
      </defs>
      <g clipPath={`url(#${id('tunnel-shape')})`} style={{isolation: 'isolate'}}>
        <rect x={x0} y={y0} width={width} height={height} fill={`url(#${id('tile')})`} />
        <rect
          x={x0}
          y={y0}
          width={width}
          height={height}
          fill={tint(from.palette.glow)}
          mask={`url(#${id('tunnel-before-mask')})`}
          style={{mixBlendMode: 'multiply'}}
        />
        <rect
          x={x0}
          y={y0}
          width={width}
          height={height}
          fill={tint(to.palette.glow)}
          mask={`url(#${id('tunnel-change-mask')})`}
          style={{mixBlendMode: 'multiply'}}
        />
        <rect x={x0} y={y0} width={width} height={height} fill={`url(#${id('tunnel-round')})`} style={{mixBlendMode: 'multiply'}} />
        <ellipse
          cx={trainX}
          cy={lineY - 60}
          rx={300}
          ry={210}
          fill={`url(#${id('tunnel-train-light')})`}
          opacity={trainLight}
          style={{mixBlendMode: 'screen'}}
        />
        <circle cx={middle} cy={lineY - 60} r={260} fill={`url(#${id('tunnel-flash')})`} opacity={flash} style={{mixBlendMode: 'screen'}} />
        <rect x={x0} y={y0} width={width} height={height} fill={`url(#${id('tunnel-portal')})`} />
      </g>
      <path d={outline} fill="none" stroke={css(night, 0.9)} strokeWidth={8} />
      <Badge line={from.line} x={x0 + 62} y={y0 + 52} size={60} />
      <Badge line={to.line} x={x1 - 62} y={y0 + 52} size={60} />
    </g>
  );
};

// The two dark mouths of the tunnel, drawn under the train: the train runs into the dark before the wall hides it,
// so the wall reads as a tunnel and not as a box in front of the line.
export const TunnelMouths = ({x0, x1, lineY}: {x0: number; x1: number; lineY: number}) => {
  const id = useSvgId();
  const cy = lineY - 64;
  return (
    <g>
      <defs>
        <radialGradient id={id('mouth')}>
          <stop offset={0} stopColor={css(night, 1)} />
          <stop offset={0.8} stopColor={css(night, 0.92)} />
          <stop offset={1} stopColor={css(night, 0.6)} />
        </radialGradient>
        <clipPath id={id('ground')}>
          <rect x={x0 - 60} y={cy - 130} width={x1 - x0 + 120} height={lineY + 14 - (cy - 130)} />
        </clipPath>
      </defs>
      {[x0, x1].map((x) => (
        <g key={x} clipPath={`url(#${id('ground')})`}>
          <ellipse cx={x} cy={cy} rx={40} ry={110} fill="#d9d4c8" />
          <ellipse cx={x} cy={cy} rx={32} ry={102} fill={`url(#${id('mouth')})`} />
        </g>
      ))}
    </g>
  );
};
