import { Composition } from "remotion";
import { LifelifyPromo } from "./LifelifyPromo";

export const FPS = 30;
export const DURATION_IN_FRAMES = 30 * FPS;
export const WIDTH = 1080;
export const HEIGHT = 1920;

export const RemotionRoot = () => {
  return (
    <Composition
      id="LifelifyPromoReel"
      component={LifelifyPromo}
      durationInFrames={DURATION_IN_FRAMES}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  );
};
