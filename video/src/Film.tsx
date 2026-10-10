import {AbsoluteFill, Audio, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {inter} from './fonts';

// An empty frame: the name of the app fades in, and the music plays under it.
export const Film = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const opacity = interpolate(frame, [0, fps / 2], [0, 1], {extrapolateRight: 'clamp'});
  const volume = interpolate(frame, [durationInFrames - fps, durationInFrames], [1, 0], {extrapolateLeft: 'clamp'});

  return (
    <AbsoluteFill style={{backgroundColor: '#0b1f3a', justifyContent: 'center', alignItems: 'center'}}>
      <div style={{fontFamily: inter, fontWeight: 700, fontSize: 160, color: 'white', opacity}}>TROME</div>
      <Audio src={staticFile('music.wav')} volume={volume} />
    </AbsoluteFill>
  );
};
