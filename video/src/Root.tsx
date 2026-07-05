import {Composition} from 'remotion';
import {HelloWorld} from './HelloWorld';
import {LapisDemo} from './demo/LapisDemo';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="LapisDemo"
        component={LapisDemo}
        durationInFrames={660}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="HelloWorld"
        component={HelloWorld}
        durationInFrames={150}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          titleText: 'Welcome to Remotion',
          titleColor: '#000000',
        }}
      />
    </>
  );
};
