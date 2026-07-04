import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

export const HelloWorld: React.FC<{
  titleText: string;
  titleColor: string;
}> = ({titleText, titleColor}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();

  const scale = spring({
    frame,
    fps,
    config: {
      damping: 200,
    },
  });

  const opacity = interpolate(
    frame,
    [durationInFrames - 25, durationInFrames - 15],
    [1, 0],
    {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    }
  );

  return (
    <AbsoluteFill
      style={{
        backgroundColor: 'white',
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      <h1
        style={{
          fontFamily: 'Helvetica, Arial, sans-serif',
          fontSize: 100,
          fontWeight: 'bold',
          color: titleColor,
          transform: `scale(${scale})`,
          opacity,
        }}
      >
        {titleText}
      </h1>
    </AbsoluteFill>
  );
};
