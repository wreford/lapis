import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {font, theme, uiFont} from './theme';

type Span = {t: string; c?: string};

const K = theme.keyword;
const S = theme.string;
const R = theme.route;
const C = theme.comment;
const I = theme.ident;

// Condensed from example.moon at the repo root
const LINES: Span[][] = [
  [{t: 'lapis = ', c: I}, {t: 'require ', c: K}, {t: '"lapis"', c: S}],
  [
    {t: 'import ', c: K},
    {t: 'Model '},
    {t: 'from require ', c: K},
    {t: '"lapis.models"', c: S},
  ],
  [],
  [{t: 'class ', c: K}, {t: 'Users '}, {t: 'extends ', c: K}, {t: 'Model'}],
  [],
  [
    {t: 'class extends ', c: K},
    {t: 'lapis.Application'},
  ],
  [
    {t: '  ['},
    {t: 'list_users', c: I},
    {t: ': '},
    {t: '"/users"', c: R},
    {t: ']: =>'},
  ],
  [
    {t: '    users = Users\\select!'},
    {t: '  -- all the users', c: C},
  ],
  [{t: '    @html ->', c: I}],
  [{t: '      ul ->'}],
  [{t: '        for ', c: K}, {t: 'user '}, {t: 'in ', c: K}, {t: '*users'}],
  [{t: '          li user.name'}],
  [],
  [
    {t: '  ['},
    {t: 'user', c: I},
    {t: ': '},
    {t: '"/profile/:id"', c: R},
    {t: ']: =>'},
  ],
  [{t: '    user = Users\\find id: @params.id'}],
  [
    {t: '    return ', c: K},
    {t: 'status: '},
    {t: '404', c: R},
    {t: ' unless ', c: K},
    {t: 'user'},
  ],
  [{t: '    @html -> h2 user.name', c: I}],
];

const TYPE_START = 20;
const CHARS_PER_FRAME = 2.2;

const lineLength = (line: Span[]) =>
  line.reduce((n, s) => n + s.t.length, 0) || 1; // empty line costs 1 "char"

export const CodeScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();

  const windowIn = spring({frame, fps, config: {damping: 16, mass: 0.7}});
  const fadeOut = interpolate(
    frame,
    [durationInFrames - 12, durationInFrames],
    [1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
  );

  let budget = Math.max(0, (frame - TYPE_START) * CHARS_PER_FRAME);
  const cursorOn = Math.floor(frame / 8) % 2 === 0;

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
          width: 1460,
          transform: `scale(${windowIn}) translateY(${(1 - windowIn) * 60}px)`,
          background: theme.panel,
          border: `2px solid ${theme.panelBorder}`,
          borderRadius: 18,
          boxShadow: '0 40px 90px rgba(0,0,0,0.55)',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            padding: '18px 24px',
            background: theme.bgLight,
            borderBottom: `2px solid ${theme.panelBorder}`,
          }}
        >
          {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
            <div
              key={c}
              style={{width: 18, height: 18, borderRadius: 9, background: c}}
            />
          ))}
          <div
            style={{
              fontFamily: uiFont,
              fontSize: 26,
              color: theme.textDim,
              marginLeft: 14,
            }}
          >
            app.moon
          </div>
        </div>
        <div style={{padding: '30px 40px', minHeight: 760}}>
          {LINES.map((line, i) => {
            const cost = lineLength(line);
            const visible = Math.max(0, Math.min(cost, Math.floor(budget)));
            const isTypingHere = budget > 0 && budget < cost;
            budget -= cost;
            let remaining = visible;
            return (
              <div
                key={i}
                style={{
                  fontFamily: font,
                  fontSize: 32,
                  lineHeight: '42px',
                  whiteSpace: 'pre',
                }}
              >
                {line.map((span, j) => {
                  const shown = span.t.slice(0, Math.max(0, remaining));
                  remaining -= span.t.length;
                  return (
                    <span key={j} style={{color: span.c ?? theme.plain}}>
                      {shown}
                    </span>
                  );
                })}
                {isTypingHere && cursorOn ? (
                  <span style={{color: theme.gold}}>▍</span>
                ) : null}
                {line.length === 0 ? ' ' : ''}
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};
