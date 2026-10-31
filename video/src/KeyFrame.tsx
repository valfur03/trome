import {AbsoluteFill} from 'remotion';
import {type Beat, type Lang, type Look, lineColours} from './arrival';
import {inter} from './fonts';
import {Phone, bezel, captureOf, card} from './Phone';
import {css, night, palette, type RGB} from './palette';
import {film} from './timing';

// One key frame of the storyboard of the arrival, in one of its two looks. In both, the phone is as large as it can
// be and stay whole across the film, and the first beat cuts it in half at the bottom edge.
// - look A, "night": a black stage; in the montage the phone hangs from the top edge, so the clock is cut off and the
//   card is the subject; a pool of the line's colour lights the bottom, where the word is, centred, in white;
// - look B, "field": the lit field of the store pictures, in the line's colour, which changes at each cut; the phone
//   rises from the bottom edge, so the whole lock screen shows, clock and card; the word is large, at the top left.

const rgb = (value: number): RGB => [(value >> 16) & 255, (value >> 8) & 255, value & 255];
const lineOf = (beat: Beat) => {
  const colour = rgb(lineColours[beat.line]);
  return {colour, tones: palette({name: beat.line, mode: beat.line === 'B' ? 'rer' : 'metro', colour, text: [255, 255, 255]})};
};

// Both looks show the phone at the largest scale at which it is whole across the film (864 of 886 pixels).
const scales = {a: 0.64, b: 0.64} as const;

// The y of the centre of the card in the film, for each beat with a phone; 'half' cuts the phone in half at the
// bottom edge (the first beat: only the top of the lock screen shows).
const cardY: Record<Look, Record<string, number | 'half'>> = {
  a: {'1-light': 'half', '2-already': 780, '3-hub': 880, '4-fork': 700, '5-rer': 840, '6-every': 760},
  b: {'1-light': 'half', '2-already': 1700, '3-hub': 1640, '4-fork': 1720, '5-rer': 1660, '6-every': 1740},
};

const phoneTop = (look: Look, beat: Beat) => {
  const scale = scales[look];
  const y = cardY[look][beat.id];
  if (y === 'half') return film.height - (bezel.height * scale) / 2;
  return y - (bezel.screen.y + (card.top + card.bottom) / 2) * scale;
};

const Word = ({look, text, hung}: {look: Look; text: string; hung: boolean}) =>
  look === 'a' ? (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: hung ? 1420 : 260,
        textAlign: 'center',
        fontFamily: inter,
        fontWeight: 700,
        fontSize: 92,
        letterSpacing: -1.5,
        color: 'white',
      }}
    >
      {text}
    </div>
  ) : (
    <div
      style={{
        position: 'absolute',
        left: 64,
        width: 760,
        top: 72,
        fontFamily: inter,
        fontWeight: 800,
        fontSize: 104,
        lineHeight: 1,
        letterSpacing: -3,
        color: 'white',
      }}
    >
      {text}
    </div>
  );

// The light of look A: a pool of the line's colour on the black, on the side where the phone is not.
const Pool = ({colour, atTop, strength}: {colour: RGB; atTop: boolean; strength: number}) => (
  <div
    style={{
      position: 'absolute',
      left: -400,
      width: film.width + 800,
      top: atTop ? -700 : film.height - 700,
      height: 1400,
      background: `radial-gradient(ellipse at center, ${css(colour, 0.5 * strength)} 0%, ${css(colour, 0.16 * strength)} 38%, ${css(colour, 0)} 68%)`,
    }}
  />
);

// The field of look B: the store pictures' lit field, with its light behind the word.
const Field = ({tones}: {tones: ReturnType<typeof palette>}) => (
  <AbsoluteFill style={{backgroundColor: css(tones.field)}}>
    <div
      style={{
        position: 'absolute',
        left: -500,
        top: -600,
        width: 1600,
        height: 1500,
        background: `radial-gradient(ellipse at center, ${css(tones.glow, 0.85)} 0%, ${css(tones.glow, 0.3)} 40%, ${css(tones.glow, 0)} 70%)`,
      }}
    />
  </AbsoluteFill>
);

// The end card: the name alone. The icon is left out: its "013" runs off its own edges, which reads as an icon cut
// in two at the size of a film (the prompter's remark on the end card of round 1).
const EndCard = ({look, beat}: {look: Look; beat: Beat}) => {
  const {colour, tones} = lineOf(beat);
  return (
    <AbsoluteFill style={{backgroundColor: css(night)}}>
      {look === 'a' ? <Pool colour={colour} atTop={false} strength={0.7} /> : <Field tones={tones} />}
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <div style={{fontFamily: inter, fontWeight: 800, fontSize: 168, letterSpacing: 4, color: 'white'}}>TROME</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const KeyFrame = ({look, lang, beat}: {look: Look; lang: Lang; beat: Beat}) => {
  if (!beat.capture) return <EndCard look={look} beat={beat} />;
  const {colour, tones} = lineOf(beat);
  const top = phoneTop(look, beat);
  const half = cardY[look][beat.id] === 'half';
  // The phone hangs from the top edge when its top is above the picture.
  const hung = top < 0;
  return (
    <AbsoluteFill style={{backgroundColor: css(night)}}>
      {look === 'a' ? <Pool colour={colour} atTop={!hung} strength={half ? 0.45 : 1} /> : <Field tones={tones} />}
      <Phone src={captureOf(beat.capture, lang)} scale={scales[look]} centreX={film.width / 2} top={top} />
      {beat.word ? <Word look={look} text={beat.word[lang]} hung={hung} /> : null}
    </AbsoluteFill>
  );
};
