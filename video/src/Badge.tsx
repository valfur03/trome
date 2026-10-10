import {inter} from './fonts';
import {css, type Line} from './palette';

// The line badge of the store pictures: round for the metro, a square with round corners for the RER, with a white rim.
export const Badge = ({line, x, y, size}: {line: Line; x: number; y: number; size: number}) => {
  const rim = (size * 9) / 130;
  const corner = (size * 26) / 130;
  const shape = (grow: number, fill: string) =>
    line.mode === 'metro' ? (
      <circle cx={x} cy={y} r={size / 2 + grow} fill={fill} />
    ) : (
      <rect x={x - size / 2 - grow} y={y - size / 2 - grow} width={size + 2 * grow} height={size + 2 * grow} rx={corner + grow} fill={fill} />
    );
  return (
    <g>
      {shape(rim, 'white')}
      {shape(0, css(line.colour))}
      <text
        x={x}
        y={y + size * 0.215}
        textAnchor="middle"
        fontFamily={inter}
        fontWeight={700}
        fontSize={size * 0.6}
        fill={css(line.text)}
      >
        {line.name}
      </text>
    </g>
  );
};
