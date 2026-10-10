import {Composition} from 'remotion';
import {Film} from './Film';
import {Stills, languages, stills} from './Stills';
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
      durationInFrames={stills.length * languages.length}
    />
    <Composition id="Storyboard" component={Storyboard} width={storyboard.width} height={storyboard.height} fps={film.fps} durationInFrames={1} />
  </>
);
