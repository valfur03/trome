import {AbsoluteFill, Img, staticFile, useCurrentFrame} from 'remotion';
import {Field, LineDrawing, Trail, strokeWidth, type Segment} from './Canvas';
import {Headline, LockCut, capture, lockCut, type Lang} from './LockCut';
import {SignatureScene, layout} from './Signature';
import {Metro} from './Vehicles';
import {inter} from './fonts';
import {K, film} from './timing';
import {css, lines, night, palette} from './palette';

// The key frames of the storyboard, one per frame of the composition, at the size of the film.
// They are drawn with the same parts as the clip, so round 2 starts from them.

export const beats = {
  lock: {fr: ['Vos prochains trains,', 'sur l’écran verrouillé.'], en: ['Your next trains,', 'on your lock screen.']},
  countdown: {fr: ['Les minutes défilent,', 'toutes seules.'], en: ['Minutes tick down,', 'on their own.']},
  fork: {fr: ['Métro et RER,', 'même à une fourche.'], en: ['Metro and RER,', 'even at a fork.']},
} as const;

const metro1 = palette(lines.metro1);

// The minutes of the card, lit: the times count down by themselves (round 2 shows them change, in a real capture).
const MinutesLight = () => {
  const x = (film.width - lockCut.width) / 2 + 660 * lockCut.scale;
  const y = (1432 - lockCut.rowsTop) * lockCut.scale;
  const width = 170 * lockCut.scale;
  const height = 156 * lockCut.scale;
  return (
    <div
      style={{
        position: 'absolute',
        left: x - 8,
        top: y - 8,
        width: width + 16,
        height: height + 16,
        borderRadius: 22,
        border: `4px solid ${css(metro1.accent)}`,
        boxShadow: `0 0 36px ${css(metro1.glow, 0.9)}, inset 0 0 24px ${css(metro1.glow, 0.5)}`,
      }}
    />
  );
};

// The fork of line 7: after a station, a branch peels off at 45 degrees and ends at a terminus, as on a map.
const ForkScene = ({lang}: {lang: Lang}) => {
  const p = palette(lines.metro7);
  const y = layout.lineY;
  const segments: Segment[] = [{from: -200, to: film.width + 200, palette: p, dots: [180, 640, 820]}];
  const forkAt = 430;
  const drop = 110;
  const end = 800;
  const nose = 330;
  return (
    <AbsoluteFill>
      <svg width={film.width} height={film.height} style={{position: 'absolute'}}>
        <Field segments={segments} camera={0} glowY={layout.headlineY} />
        <LineDrawing segments={segments} y={y} />
        <path
          d={`M ${forkAt} ${y} L ${forkAt + drop} ${y + drop} H ${end}`}
          fill="none"
          stroke={css(p.stroke)}
          strokeWidth={strokeWidth}
          strokeLinejoin="round"
        />
        {[660, 760].map((x) => (
          <circle key={x} cx={x} cy={y + drop} r={14 * K} fill="white" />
        ))}
        <rect x={end - 5} y={y + drop - strokeWidth / 2 - 7} width={10} height={strokeWidth + 14} fill="white" />
        <Trail nose={nose} length={400} y={y} palette={p} />
        <Metro palette={p} x={nose} y={y - strokeWidth / 2} />
      </svg>
      <LockCut layers={[{src: capture('fork', lang), opacity: 1}]} />
      <Headline lines={beats.fork[lang]} accent={p.accent} centreY={layout.headlineY} />
    </AbsoluteFill>
  );
};

// The end card: the icon of the app and its name, on the night of the canvas, lit by the yellow of the icon.
export const EndCard = () => {
  const icon = 300;
  return (
    <AbsoluteFill style={{backgroundColor: css(night), alignItems: 'center', justifyContent: 'center'}}>
      <div
        style={{
          position: 'absolute',
          width: 1100,
          height: 1100,
          left: (film.width - 1100) / 2,
          top: film.height / 2 - 650,
          background: `radial-gradient(circle, ${css(metro1.glow, 0.55)} 0%, ${css(metro1.glow, 0.18)} 40%, ${css(metro1.glow, 0)} 70%)`,
        }}
      />
      <Img
        src={staticFile('app/app-icon.png')}
        style={{
          width: icon,
          height: icon,
          borderRadius: icon * 0.2237,
          // The icon is black: a faint rim, as iOS draws around a dark icon, keeps its shape on the night.
          boxShadow: '0 0 0 2px rgba(255, 255, 255, 0.16), 0 24px 80px rgba(0, 0, 0, 0.6)',
        }}
      />
      <div style={{marginTop: 64, fontFamily: inter, fontWeight: 700, fontSize: 120, letterSpacing: 2, color: 'white'}}>TROME</div>
    </AbsoluteFill>
  );
};

// One still per frame: the five key frames of the storyboard, in French then in English.
export const stills = [
  {name: '1-lock', render: (lang: Lang) => <SignatureScene t={0.5} lang={lang} headline={beats.lock[lang]} />},
  {name: '2-countdown', render: (lang: Lang) => <SignatureScene t={1.1} lang={lang} headline={beats.countdown[lang]} overlay={<MinutesLight />} />},
  {name: '3-tunnel', render: (lang: Lang) => <SignatureScene t={2.45} lang={lang} />},
  {name: '4-fork', render: (lang: Lang) => <ForkScene lang={lang} />},
  {name: '5-end', render: () => <EndCard />},
] as const;

export const languages: Lang[] = ['fr', 'en'];

export const Stills = () => {
  const frame = useCurrentFrame();
  const still = stills[frame % stills.length];
  const lang = languages[Math.floor(frame / stills.length)];
  return <AbsoluteFill style={{backgroundColor: 'black'}}>{still.render(lang)}</AbsoluteFill>;
};
