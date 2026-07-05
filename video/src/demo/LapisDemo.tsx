import {AbsoluteFill, Sequence} from 'remotion';
import {CodeScene} from './CodeScene';
import {Features} from './Features';
import {Outro} from './Outro';
import {theme} from './theme';
import {Title} from './Title';

// 30 fps scene layout, 660 frames (22s) total
export const LapisDemo: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(1200px 800px at 50% 35%, ${theme.bgLight}, ${theme.bg})`,
      }}
    >
      <Sequence durationInFrames={105}>
        <Title />
      </Sequence>
      <Sequence from={105} durationInFrames={300}>
        <CodeScene />
      </Sequence>
      <Sequence from={405} durationInFrames={165}>
        <Features />
      </Sequence>
      <Sequence from={570} durationInFrames={90}>
        <Outro />
      </Sequence>
    </AbsoluteFill>
  );
};
