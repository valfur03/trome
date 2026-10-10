import {AbsoluteFill} from 'remotion';
import {stills} from './Stills';
import {inter} from './fonts';
import {film} from './timing';

// The storyboard on one page: the plan in five lines, then the key frame of each beat at one third of its size.

export const storyboard = {
  lines: [
    'Muted, 24 s, portrait 886 x 1920, French first. A stranger learns: the next trains are on the lock screen, nothing to open; the minutes count down by themselves; when I change lines, the card follows; metro and RER, even at a fork.',
    '0–5 s: the real lock screen card (line 1) above the line, a metro runs along it. “Vos prochains trains, sur l’écran verrouillé.” / “Your next trains, on your lock screen.”',
    '5–9 s: the minutes change in a real capture, lit, while the train nears the station. “Les minutes défilent, toutes seules.” / “Minutes tick down, on their own.”',
    '9–17 s: the metro goes into the tiled tunnel and comes out as an RER on line B; the card turns to line B. “Changez de ligne, la carte suit.” / “Change lines, the card follows.” 17–21 s: line 7 forks; the card shows one row per branch. “Métro et RER, même à une fourche.” / “Metro and RER, even at a fork.”',
    '21–24 s: the end card, the icon and TROME; the music fades out.',
  ],
  times: ['0–5 s', '5–9 s', '9–17 s', '17–21 s', '21–24 s'],
  width: 1735,
  height: 1170,
} as const;

const third = 1 / 3;

export const Storyboard = () => (
  <AbsoluteFill style={{backgroundColor: '#f4f3ef', padding: 50, fontFamily: inter, color: '#16171c'}}>
    <ol style={{margin: 0, paddingLeft: 32, fontSize: 23, lineHeight: 1.4}}>
      {storyboard.lines.map((line) => (
        <li key={line} style={{marginBottom: 6}}>
          {line}
        </li>
      ))}
    </ol>
    <div style={{display: 'flex', gap: 40, marginTop: 28}}>
      {stills.map((still, i) => (
        <div key={still.name}>
          <div style={{fontSize: 24, fontWeight: 700, marginBottom: 10}}>{storyboard.times[i]}</div>
          <div style={{width: film.width * third, height: film.height * third, overflow: 'hidden', borderRadius: 12, position: 'relative'}}>
            <div style={{width: film.width, height: film.height, transform: `scale(${third})`, transformOrigin: 'top left', position: 'absolute'}}>
              {still.render('fr')}
            </div>
          </div>
        </div>
      ))}
    </div>
  </AbsoluteFill>
);
