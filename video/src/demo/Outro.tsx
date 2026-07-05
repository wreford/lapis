import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {font, theme, uiFont} from './theme';

export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  const s = spring({frame, fps, config: {damping: 14, mass: 0.8}});
  const pill = spring({frame: frame - 14, fps, config: {damping: 200}});
  const pulse = 1 + Math.sin(frame / 9) * 0.012;

  return (
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
      <div
        style={{
          fontFamily: uiFont,
          fontSize: 92,
          fontWeight: 800,
          color: theme.text,
          transform: `scale(${s})`,
        }}
      >
        Start building
      </div>
      <div
        style={{
          marginTop: 56,
          opacity: pill,
          transform: `scale(${pill * pulse})`,
          fontFamily: font,
          fontSize: 46,
          color: theme.bg,
          fontWeight: 700,
          padding: '26px 60px',
          borderRadius: 60,
          background: `linear-gradient(90deg, ${theme.blue}, ${theme.gold})`,
        }}
      >
        leafo.net/lapis
      </div>
      <div
        style={{
          marginTop: 44,
          fontFamily: uiFont,
          fontSize: 30,
          color: theme.textDim,
          opacity: interpolate(frame, [24, 40], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
        }}
      >
        Powering itch.io &amp; rocks.moonscript.org
      </div>
    </AbsoluteFill>
  );
};
