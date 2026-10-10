// The colours of the film, made the way the store pictures make theirs: every colour of a scene
// comes from the hue of the line colour that the app shows (the transport data of the app).
export type RGB = readonly [number, number, number];

export type Line = {
  name: string;
  mode: 'metro' | 'rer';
  colour: RGB;
  text: RGB;
};

const hex = (value: number): RGB => [(value >> 16) & 255, (value >> 8) & 255, value & 255];

// The line colours of the app's transport data (stations.json of the app).
export const lines = {
  metro1: {name: '1', mode: 'metro', colour: hex(0xffbe00), text: hex(0x000000)},
  metro7: {name: '7', mode: 'metro', colour: hex(0xff82b4), text: hex(0x000000)},
  rerB: {name: 'B', mode: 'rer', colour: hex(0x5091cb), text: hex(0xffffff)},
} as const satisfies Record<string, Line>;

export const night: RGB = hex(0x05060d);
export const white: RGB = [255, 255, 255];

function hue([r, g, b]: RGB): number {
  const [rn, gn, bn] = [r / 255, g / 255, b / 255];
  const max = Math.max(rn, gn, bn);
  const delta = max - Math.min(rn, gn, bn);
  if (delta === 0) return 0;
  const h = max === rn ? ((gn - bn) / delta) % 6 : max === gn ? (bn - rn) / delta + 2 : (rn - gn) / delta + 4;
  return (h * 60 + 360) % 360;
}

function hsl(h: number, s: number, l: number): RGB {
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const x = chroma * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - chroma / 2;
  const [r, g, b] =
    h < 60 ? [chroma, x, 0] : h < 120 ? [x, chroma, 0] : h < 180 ? [0, chroma, x] : h < 240 ? [0, x, chroma] : h < 300 ? [x, 0, chroma] : [chroma, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

export type Palette = {line: RGB; field: RGB; glow: RGB; stroke: RGB; accent: RGB};

// The same four tones as the store pictures: the lit field, the light behind the headline,
// the line drawing, and the second half of the headline.
// A yellow turns olive when it is dark: its dark tones (the field, the glow) lean to orange, as a painter's shadows do.
export function palette(line: Line): Palette {
  const h = hue(line.colour);
  const dark = h > 38 && h < 70 ? h - 14 : h;
  return {
    line: line.colour,
    field: hsl(dark, 0.7, 0.25),
    glow: hsl(dark, 0.78, 0.52),
    stroke: hsl(h, 0.9, 0.62),
    accent: hsl(h, 0.9, 0.8),
  };
}

export const css = ([r, g, b]: RGB, alpha = 1): string => `rgba(${r}, ${g}, ${b}, ${alpha})`;

export const mix = (a: RGB, b: RGB, t: number): RGB => [
  Math.round(a[0] + (b[0] - a[0]) * t),
  Math.round(a[1] + (b[1] - a[1]) * t),
  Math.round(a[2] + (b[2] - a[2]) * t),
];
