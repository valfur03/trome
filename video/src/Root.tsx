import {Composition} from 'remotion';
import {Film} from './Film';
import {film} from './timing';

export const Root = () => (
  <Composition
    id="Film"
    component={Film}
    width={film.width}
    height={film.height}
    fps={film.fps}
    durationInFrames={film.seconds * film.fps}
  />
);
