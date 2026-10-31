import {AbsoluteFill} from 'remotion';
import {KeyFrame} from './KeyFrame';
import {type Lang, beats, looks, tempo} from './arrival';
import {inter} from './fonts';
import {film} from './timing';

// The storyboard on one page, in one language: what the viewer must feel, then the key frame of each beat in each
// look at one third of its size, with its time, its word and what moves in it.

const third = 1 / 3;
const gap = 24;
const pad = 50;
const frameWidth = Math.round(film.width * third);
const frameHeight = Math.round(film.height * third);

export const storyboard = {
  width: pad * 2 + beats.length * frameWidth + (beats.length - 1) * gap + 140,
  height: 2330,
} as const;

const lookNames = {a: 'A, night', b: 'B, field'} as const;

const feel = {
  fr: 'Je marche vers une station, je n’ouvre rien, et mes prochains trains sont déjà sur l’écran verrouillé. Et c’est vrai à chaque station, sur chaque sorte de ligne : les coupes le montrent, pas des phrases.',
  en: 'I walk to a station, I open nothing, and my next trains are already on my lock screen. And it works at every station, on every kind of line: the cuts show it, not sentences.',
} as const;

export const Storyboard = ({lang}: {lang: Lang}) => (
  <AbsoluteFill style={{backgroundColor: '#f4f3ef', padding: pad, fontFamily: inter, color: '#16171c'}}>
    <div style={{fontSize: 34, fontWeight: 700}}>
      The arrival: {beats[beats.length - 1].to} s, portrait {film.width} x {film.height}, muted, {tempo.bpm} beats a minute ({lang.toUpperCase()})
    </div>
    <div style={{fontSize: 26, lineHeight: 1.35, marginTop: 10, maxWidth: 1900}}>{feel[lang]}</div>
    {looks.map((look) => (
      <div key={look} style={{display: 'flex', marginTop: 34}}>
        <div style={{width: 140, fontSize: 30, fontWeight: 700, paddingTop: 44}}>{lookNames[look]}</div>
        <div style={{display: 'flex', gap}}>
          {beats.map((beat) => (
            <div key={beat.id} style={{width: frameWidth}}>
              <div style={{fontSize: 24, fontWeight: 700, marginBottom: 8}}>
                {beat.from}–{beat.to} s{beat.word ? ` · “${beat.word[lang]}”` : ''}
              </div>
              <div style={{width: frameWidth, height: frameHeight, overflow: 'hidden', borderRadius: 10, position: 'relative'}}>
                <div style={{width: film.width, height: film.height, transform: `scale(${third})`, transformOrigin: 'top left', position: 'absolute'}}>
                  <KeyFrame look={look} lang={lang} beat={beat} />
                </div>
              </div>
              <div style={{fontSize: 17, lineHeight: 1.3, marginTop: 8, height: 92, overflow: 'hidden'}}>{beat.moves}</div>
            </div>
          ))}
        </div>
      </div>
    ))}
  </AbsoluteFill>
);
