import {css, mix, type Palette, type RGB} from './palette';
import {useSvgId} from './svgId';

// Flat side views of a metro and of a double-deck RER, drawn in our own geometry and in the line colours.
// They evoke a type of train (a long open metro with a rounded front, a tall two-level RER), never a real livery or logo.
// Each faces right: x is the tip of the nose, y the bottom of the wheels.

const glass: RGB = [16, 19, 28];

type Props = {palette: Palette; x: number; y: number};

const bogies = (length: number, cars: number, top: number) => {
  const carLength = length / cars;
  const out = [];
  for (let car = 0; car < cars; car++) {
    for (const at of [0.2, 0.8]) {
      const cx = car * carLength + at * carLength;
      out.push(
        <g key={`${car}-${at}`}>
          <rect x={cx - 24} y={top} width={48} height={8} rx={3} fill={css(glass)} />
          <circle cx={cx - 12} cy={top + 9} r={6} fill={css(glass)} />
          <circle cx={cx + 12} cy={top + 9} r={6} fill={css(glass)} />
        </g>,
      );
    }
  }
  return out;
};

// The joint between two cars of an open train: a short dark band, so the train reads as one long room.
const gangway = (x: number, top: number, bottom: number, key: string) => (
  <g key={key}>
    <rect x={x - 4} y={top} width={8} height={bottom - top} fill={css(glass, 0.85)} />
    <line x1={x} y1={top} x2={x} y2={bottom} stroke={css([255, 255, 255], 0.18)} strokeWidth={1.5} />
  </g>
);

export const metroLength = 400;
export const metroHeight = 66;

export const Metro = ({palette, x, y}: Props) => {
  const id = useSvgId();
  const L = metroLength;
  const H = metroHeight;
  const cars = 3;
  const carLength = L / cars;
  const body = mix(palette.stroke, [255, 255, 255], 0.12);
  const door = mix(body, [255, 255, 255], 0.35);
  const bodyPath = `M 10 0 H ${L - 64} C ${L - 26} 0 ${L - 4} 18 ${L} 46 V ${H - 8} Q ${L} ${H} ${L - 8} ${H} H 8 Q 0 ${H} 0 ${H - 8} V 10 Q 0 0 10 0 Z`;
  return (
    <g transform={`translate(${x - L}, ${y - H - 17})`}>
      {bogies(L, cars, H)}
      <path d={bodyPath} fill={css(body)} />
      <clipPath id={id('metro-body')}>
        <path d={bodyPath} />
      </clipPath>
      <g clipPath={`url(#${id('metro-body')})`}>
        <rect x={0} y={0} width={L} height={5} fill={css(palette.accent)} />
        <rect x={0} y={H - 15} width={L} height={15} fill={css(palette.line)} />
        {Array.from({length: cars}, (_, car) => (
          <rect key={car} x={car * carLength + 10} y={15} width={carLength - 20} height={22} rx={5} fill={css(glass)} />
        ))}
        {Array.from({length: cars}, (_, car) =>
          // The front car has one door: the cab takes the place of the second.
          (car === cars - 1 ? [0.28] : [0.28, 0.72]).map((at) => {
            const dx = car * carLength + at * carLength;
            return (
              <g key={`${car}-${at}`}>
                <rect x={dx - 13} y={9} width={26} height={H - 13} rx={3} fill={css(door)} stroke={css(glass, 0.5)} strokeWidth={1.5} />
                <rect x={dx - 10} y={15} width={8} height={26} rx={2} fill={css(glass)} />
                <rect x={dx + 2} y={15} width={8} height={26} rx={2} fill={css(glass)} />
              </g>
            );
          }),
        )}
        <path d={`M ${L - 60} 8 C ${L - 30} 8 ${L - 12} 20 ${L - 5} 42 H ${L - 56} Z`} fill={css(glass)} />
        <path d={`M ${L - 46} 13 C ${L - 30} 14 ${L - 20} 20 ${L - 15} 28`} stroke={css([255, 255, 255], 0.35)} strokeWidth={2} fill="none" />
        <ellipse cx={L - 4} cy={H - 22} rx={4} ry={3} fill="white" />
      </g>
      {[1, 2].map((n) => gangway(n * carLength, 3, H - 2, `g${n}`))}
    </g>
  );
};

export const rerLength = 430;
export const rerHeight = 96;

export const Rer = ({palette, x, y}: Props) => {
  const id = useSvgId();
  const L = rerLength;
  const H = rerHeight;
  const cars = 3;
  const carLength = L / cars;
  const body = mix(palette.stroke, [255, 255, 255], 0.12);
  const door = mix(body, [255, 255, 255], 0.35);
  const bodyPath = `M 8 0 H ${L - 40} L ${L - 2} 34 Q ${L} 36 ${L} 40 V ${H - 8} Q ${L} ${H} ${L - 8} ${H} H 8 Q 0 ${H} 0 ${H - 8} V 8 Q 0 0 8 0 Z`;
  return (
    <g transform={`translate(${x - L}, ${y - H - 17})`}>
      {bogies(L, cars, H)}
      <path d={bodyPath} fill={css(body)} />
      <clipPath id={id('rer-body')}>
        <path d={bodyPath} />
      </clipPath>
      <g clipPath={`url(#${id('rer-body')})`}>
        <rect x={0} y={0} width={L} height={5} fill={css(palette.accent)} />
        <rect x={0} y={44} width={L} height={5} fill={css(palette.accent)} />
        <rect x={0} y={H - 13} width={L} height={13} fill={css(palette.line)} />
        {Array.from({length: cars}, (_, car) => (
          <g key={car}>
            <rect x={car * carLength + 12} y={13} width={carLength - 24} height={24} rx={5} fill={css(glass)} />
            <rect x={car * carLength + 44} y={56} width={carLength - 88} height={24} rx={5} fill={css(glass)} />
          </g>
        ))}
        {Array.from({length: cars}, (_, car) =>
          (car === cars - 1 ? [0.14] : [0.14, 0.86]).map((at) => {
            const dx = car * carLength + at * carLength;
            return (
              <g key={`${car}-${at}`}>
                <rect x={dx - 13} y={52} width={26} height={H - 56} rx={3} fill={css(door)} stroke={css(glass, 0.5)} strokeWidth={1.5} />
                <rect x={dx - 10} y={58} width={8} height={22} rx={2} fill={css(glass)} />
                <rect x={dx + 2} y={58} width={8} height={22} rx={2} fill={css(glass)} />
              </g>
            );
          }),
        )}
        <path d={`M ${L - 44} 7 L ${L - 8} 36 V 42 H ${L - 44} Z`} fill={css(glass)} />
        <path d={`M ${L - 36} 14 L ${L - 20} 28`} stroke={css([255, 255, 255], 0.35)} strokeWidth={2} />
        <ellipse cx={L - 4} cy={H - 24} rx={4} ry={3} fill="white" />
      </g>
      {[1, 2].map((n) => gangway(n * carLength, 3, H - 2, `g${n}`))}
    </g>
  );
};
