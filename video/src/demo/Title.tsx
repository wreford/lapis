import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {font, theme, uiFont} from './theme';

export const Title: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();

  const scale = spring({frame, fps, config: {damping: 14, mass: 0.8}});
  const underline = spring({frame: frame - 12, fps, config: {damping: 200}});
  const subtitle = interpolate(frame, [22, 40], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const fadeOut = interpolate(
    frame,
    [durationInFrames - 12, durationInFrames],
    [1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
  );

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        opacity: fadeOut,
      }}
    >
      <div style={{transform: `scale(${scale})`, textAlign: 'center'}}>
        <div
          style={{
            fontFamily: uiFont,
            fontSize: 190,
            fontWeight: 800,
            color: theme.text,
            letterSpacing: '-0.03em',
          }}
        >
          Lapis
        </div>
        <div
          style={{
            height: 10,
            width: 420 * underline,
            margin: '10px auto 34px',
            borderRadius: 5,
            background: `linear-gradient(90deg, ${theme.blue}, ${theme.gold})`,
          }}
        />
        <div
          style={{
            fontFamily: font,
            fontSize: 44,
            color: theme.textDim,
            opacity: subtitle,
          }}
        >
          A web framework for Lua &amp; MoonScript
        </div>
      </div>
    </AbsoluteFill>
  );
};
