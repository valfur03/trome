import {AbsoluteFill, Img, staticFile} from 'remotion';
import {type Beat, type Lang, type Look, lineColours} from './arrival';
import {inter} from './fonts';
import {Phone, bezel, captureOf, card} from './Phone';
import {css, night, palette, type RGB} from './palette';
import {film} from './timing';

// One key frame of the storyboard of the arrival, in one of its two looks:
// - look A, "night": a black stage, the phone large (it fills the width), hung from the top edge or rising from the
//   bottom one in turn, a pool of the line's colour where the phone is not, the word centred in white;
// - look B, "field": the lit field of the store pictures, in the line's colour, which changes at each cut, the phone
//   smaller and always rising from the bottom edge, the word large and left-aligned at the top.

const rgb = (value: number): RGB => [(value >> 16) & 255, (value >> 8) & 255, value & 255];
const lineOf = (beat: Beat) => {
  const colour = rgb(lineColours[beat.line]);
  return {colour, tones: palette({name: beat.line, mode: beat.line === 'B' ? 'rer' : 'metro', colour, text: [255, 255, 255]})};
};

const scales = {a: 0.64, b: 0.56} as const;

// The y of the centre of the card in the film, for each beat with a phone; 'half' cuts the phone in half at the
// bottom edge (the first beat: only the top of the lock screen shows).
const cardY: Record<Look, Record<string, number | 'half'>> = {
  a: {'1-light': 'half', '2-already': 780, '3-hub': 1700, '4-fork': 720, '5-rer': 1660, '6-every': 780},
  b: {'1-light': 'half', '2-already': 1700, '3-hub': 1660, '4-fork': 1720, '5-rer': 1680, '6-every': 1700},
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
        left: 72,
        width: 742,
        top: 200,
        fontFamily: inter,
        fontWeight: 800,
        fontSize: 124,
        lineHeight: 1.02,
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

const EndCard = ({look, beat}: {look: Look; beat: Beat}) => {
  const {colour, tones} = lineOf(beat);
  const icon = 300;
  return (
    <AbsoluteFill style={{backgroundColor: css(night)}}>
      {look === 'a' ? <Pool colour={colour} atTop={false} strength={0.7} /> : <Field tones={tones} />}
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <Img
          src={staticFile('app/app-icon.png')}
          style={{
            width: icon,
            height: icon,
            borderRadius: icon * 0.2237,
            // The icon is black: a faint rim, as iOS draws around a dark icon, keeps its shape on a dark ground.
            boxShadow: '0 0 0 2px rgba(255, 255, 255, 0.16)',
          }}
        />
        <div style={{marginTop: 56, fontFamily: inter, fontWeight: 700, fontSize: 112, letterSpacing: 2, color: 'white'}}>TROME</div>
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
