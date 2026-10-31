import {Composition} from 'remotion';
import {Film} from './Film';
import {Stills} from './Stills';
import {keyFrames} from './arrival';
import {Storyboard, storyboard} from './Storyboard';
import {film} from './timing';

export const Root = () => (
  <>
    <Composition
      id="Film"
      component={Film}
      width={film.width}
      height={film.height}
      fps={film.fps}
      durationInFrames={film.seconds * film.fps}
    />
    <Composition
      id="Stills"
      component={Stills}
      width={film.width}
      height={film.height}
      fps={film.fps}
      durationInFrames={keyFrames.length}
    />
    <Composition
      id="Storyboard"
      component={Storyboard}
      width={storyboard.width}
      height={storyboard.height}
      fps={film.fps}
      durationInFrames={1}
      defaultProps={{lang: 'fr' as const}}
    />
  </>
);
