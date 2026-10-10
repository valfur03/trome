import {AbsoluteFill, Audio, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {SignatureScene} from './Signature';

// Round 1 of the film: the signature move, with the music made in code under it.
export const Film = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const volume = interpolate(frame, [durationInFrames - fps, durationInFrames], [1, 0], {extrapolateLeft: 'clamp'});

  return (
    <AbsoluteFill style={{backgroundColor: 'black'}}>
      <SignatureScene t={frame / fps} />
      <Audio src={staticFile('music.wav')} volume={volume} />
    </AbsoluteFill>
  );
};
