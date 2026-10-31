import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {KeyFrame} from './KeyFrame';
import {keyFrames} from './arrival';

// The key frames of the storyboard of the arrival, one per frame of the composition, at the size of the film:
// each look, each language, each beat (the order of keyFrames, which scripts/name-stills.ts uses to name them).
export const Stills = () => {
  const {look, lang, beat} = keyFrames[useCurrentFrame()];
  return (
    <AbsoluteFill style={{backgroundColor: 'black'}}>
      <KeyFrame look={look} lang={lang} beat={beat} />
    </AbsoluteFill>
  );
};
