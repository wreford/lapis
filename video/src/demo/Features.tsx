import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {theme, uiFont} from './theme';

const FEATURES = [
  {icon: '🌙', title: 'MoonScript & Lua', desc: 'Write apps in either language'},
  {icon: '⚡', title: 'OpenResty speed', desc: 'Runs inside Nginx via LuaJIT'},
  {icon: '🗄️', title: 'Database models', desc: 'Query builder & Model classes'},
  {icon: '🧩', title: 'HTML as code', desc: 'Build markup with plain functions'},
];

export const Features: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();

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
      <div
        style={{
          fontFamily: uiFont,
          fontSize: 64,
          fontWeight: 800,
          color: theme.text,
          marginBottom: 70,
          opacity: interpolate(frame, [0, 15], [0, 1], {
            extrapolateRight: 'clamp',
          }),
        }}
      >
        Batteries included
      </div>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: 40,
          width: 1360,
        }}
      >
        {FEATURES.map((f, i) => {
          const s = spring({
            frame: frame - 8 - i * 9,
            fps,
            config: {damping: 15, mass: 0.7},
          });
          return (
            <div
              key={f.title}
              style={{
                transform: `scale(${s}) translateY(${(1 - s) * 40}px)`,
                opacity: s,
                background: theme.panel,
                border: `2px solid ${theme.panelBorder}`,
                borderRadius: 20,
                padding: '38px 44px',
                display: 'flex',
                alignItems: 'center',
                gap: 30,
              }}
            >
              <div style={{fontSize: 66}}>{f.icon}</div>
              <div>
                <div
                  style={{
                    fontFamily: uiFont,
                    fontSize: 40,
                    fontWeight: 700,
                    color: theme.blue,
                  }}
                >
                  {f.title}
                </div>
                <div
                  style={{
                    fontFamily: uiFont,
                    fontSize: 30,
                    color: theme.textDim,
                    marginTop: 8,
                  }}
                >
                  {f.desc}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
