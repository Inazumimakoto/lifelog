import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

type Scene = {
  start: number;
  end: number;
  eyebrow: string;
  title: string;
  subtitle: string;
  image: string;
  accent: string;
  align?: "left" | "right";
  scale?: number;
  y?: number;
};

const scenes: Scene[] = [
  {
    start: 3.2,
    end: 7.2,
    eyebrow: "TODAY",
    title: "今日の全部が、\nひと目でわかる",
    subtitle: "予定、タスク、メモ、日記まで。",
    image: "captures/01-home.png",
    accent: "#0A84FF",
    align: "right",
    scale: 0.88,
    y: 170,
  },
  {
    start: 7.0,
    end: 11.1,
    eyebrow: "CALENDAR",
    title: "月も週も、\n予定がすぐ見える",
    subtitle: "外部カレンダーも、アプリ内予定も。",
    image: "captures/03-calendar-week.png",
    accent: "#FF8A1F",
    align: "left",
    scale: 0.88,
    y: 130,
  },
  {
    start: 10.9,
    end: 14.9,
    eyebrow: "DIARY",
    title: "気分と体調を、\n日記に残す",
    subtitle: "あとからカレンダーで振り返れる。",
    image: "captures/08-diary-detail.png",
    accent: "#FF4D8D",
    align: "right",
    scale: 0.9,
    y: 145,
  },
  {
    start: 14.7,
    end: 18.9,
    eyebrow: "HABITS",
    title: "続けた日々が、\nちゃんと見える",
    subtitle: "習慣の積み上げをヒートマップで。",
    image: "captures/05-habits.png",
    accent: "#24B45A",
    align: "left",
    scale: 0.88,
    y: 135,
  },
  {
    start: 18.7,
    end: 23.0,
    eyebrow: "LOCK SCREEN",
    title: "ロック画面にも、\n予定を置ける",
    subtitle: "アプリを開く前に、今日を確認。",
    image: "lock-screen-calendar.png",
    accent: "#7C5CFF",
    align: "right",
    scale: 1.05,
    y: 180,
  },
  {
    start: 22.8,
    end: 26.4,
    eyebrow: "PRIVATE",
    title: "日記もメモも、\n自分のために",
    subtitle: "アプリロックとローカル中心の管理。",
    image: "captures/09-settings.png",
    accent: "#111111",
    align: "left",
    scale: 0.9,
    y: 170,
  },
];

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const softEase = Easing.bezier(0.16, 1, 0.3, 1);
const editorialEase = Easing.bezier(0.45, 0, 0.55, 1);

const sec = (seconds: number, fps: number) => Math.round(seconds * fps);

export const LifelifyPromo = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill
      style={{
        background: "#F7F4EE",
        color: "#101010",
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Hiragino Sans", "Yu Gothic", "Noto Sans JP", sans-serif',
        overflow: "hidden",
      }}
    >
      <Texture />
      <Intro />
      {scenes.map((scene) => (
        <FeatureScene key={scene.eyebrow} scene={scene} />
      ))}
      <FinalCard />
      <ProgressPill progress={frame / (30 * fps)} />
    </AbsoluteFill>
  );
};

const Texture = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const drift = interpolate(frame, [0, 30 * fps], [0, 70], clamp);

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(160deg, #fffaf1 0%, #f4f8ff 42%, #f7fbf2 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: -220 + drift,
          left: -110,
          width: 1300,
          height: 620,
          transform: "rotate(-11deg)",
          background:
            "linear-gradient(90deg, rgba(10,132,255,0.10), rgba(255,138,31,0.10), rgba(36,180,90,0.08))",
          borderRadius: 72,
        }}
      />
      <div
        style={{
          position: "absolute",
          right: -250,
          bottom: 120,
          width: 860,
          height: 420,
          transform: "rotate(15deg)",
          background: "rgba(255,255,255,0.68)",
          border: "1px solid rgba(0,0,0,0.05)",
          borderRadius: 64,
        }}
      />
    </AbsoluteFill>
  );
};

const Intro = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = interpolate(frame, [0, sec(0.8, fps)], [0, 1], {
    ...clamp,
    easing: softEase,
  });
  const exit = interpolate(frame, [sec(2.55, fps), sec(3.2, fps)], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });
  const visible = enter * (1 - exit);
  const phoneIn = interpolate(frame, [sec(0.35, fps), sec(1.35, fps)], [0, 1], {
    ...clamp,
    easing: softEase,
  });

  return (
    <AbsoluteFill
      style={{
        opacity: visible,
        transform: `translateY(${interpolate(visible, [0, 1], [24, 0])}px)`,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 150,
          left: 80,
          display: "flex",
          alignItems: "center",
          gap: 24,
        }}
      >
        <Img
          src={staticFile("lifelify-icon.png")}
          style={{
            width: 112,
            height: 112,
            borderRadius: 26,
            boxShadow: "0 22px 70px rgba(0,0,0,0.20)",
          }}
        />
        <div>
          <div style={{ fontSize: 38, fontWeight: 800, color: "#6E6E73" }}>
            lifelify
          </div>
          <div style={{ fontSize: 24, fontWeight: 700, color: "#0A84FF" }}>
            30秒紹介
          </div>
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          left: 78,
          top: 340,
          width: 850,
          fontSize: 94,
          lineHeight: 1.08,
          fontWeight: 900,
          letterSpacing: 0,
        }}
      >
        日記も、
        <br />
        予定も、
        <br />
        習慣も。
      </div>

      <div
        style={{
          position: "absolute",
          left: 82,
          top: 680,
          fontSize: 42,
          lineHeight: 1.3,
          fontWeight: 800,
          color: "#333333",
        }}
      >
        毎日の記録を、ひとつのアプリに。
      </div>

      <PhoneShot
        image="captures/01-home.png"
        accent="#0A84FF"
        width={520}
        top={905 - phoneIn * 34}
        left={278}
        opacity={phoneIn}
        rotate={interpolate(phoneIn, [0, 1], [6, -3])}
        scale={interpolate(phoneIn, [0, 1], [0.92, 1])}
      />
    </AbsoluteFill>
  );
};

const FeatureScene = ({ scene }: { scene: Scene }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const start = sec(scene.start, fps);
  const end = sec(scene.end, fps);
  const local = frame - start;
  const enter = interpolate(frame, [start, start + sec(0.7, fps)], [0, 1], {
    ...clamp,
    easing: softEase,
  });
  const exit = interpolate(frame, [end - sec(0.55, fps), end], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });
  const visible = enter * (1 - exit);
  const imageX = scene.align === "left" ? 72 : 430;
  const textX = 76;
  const phoneTilt = scene.align === "left" ? -3 : 3;
  const float = Math.sin(local / fps / 1.7) * 10;
  const textSlide = interpolate(enter, [0, 1], [56, 0]);
  const imageSlide = interpolate(enter, [0, 1], [scene.align === "left" ? -70 : 70, 0]);

  return (
    <AbsoluteFill style={{ opacity: visible }}>
      <AccentBand color={scene.accent} progress={enter} align={scene.align ?? "right"} />
      <PhoneShot
        image={scene.image}
        accent={scene.accent}
        width={scene.image === "lock-screen-calendar.png" ? 440 : 560}
        top={(scene.y ?? 140) + float}
        left={imageX + imageSlide}
        rotate={phoneTilt}
        scale={scene.scale ?? 0.9}
        opacity={visible}
        compact={scene.image === "lock-screen-calendar.png"}
      />
      <div
        style={{
          position: "absolute",
          left: textX,
          top: 1195,
          width: 900,
          transform: `translateY(${textSlide}px)`,
          textShadow:
            "0 5px 26px rgba(247,244,238,0.98), 0 2px 8px rgba(247,244,238,0.95)",
        }}
      >
        <div
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 12,
            padding: "12px 18px",
            borderRadius: 999,
            background: "rgba(255,255,255,0.86)",
            border: "1px solid rgba(0,0,0,0.06)",
            color: scene.accent,
            fontSize: 25,
            fontWeight: 900,
          }}
        >
          <span
            style={{
              width: 13,
              height: 13,
              borderRadius: 999,
              background: scene.accent,
              display: "inline-block",
            }}
          />
          {scene.eyebrow}
        </div>
        <div
          style={{
            marginTop: 26,
            whiteSpace: "pre-line",
            fontSize: 62,
            lineHeight: 1.12,
            fontWeight: 950,
            letterSpacing: 0,
          }}
        >
          {scene.title}
        </div>
        <div
          style={{
            marginTop: 24,
            fontSize: 31,
            lineHeight: 1.42,
            fontWeight: 760,
            color: "#4B4B4F",
          }}
        >
          {scene.subtitle}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const AccentBand = ({
  color,
  progress,
  align,
}: {
  color: string;
  progress: number;
  align: "left" | "right";
}) => {
  return (
    <div
      style={{
        position: "absolute",
        top: 78,
        left: align === "left" ? -220 : 500,
        width: 780,
        height: 1420,
        borderRadius: 80,
        transform: `rotate(${align === "left" ? -8 : 8}deg) scale(${interpolate(
          progress,
          [0, 1],
          [0.96, 1],
        )})`,
        background: color,
        opacity: 0.1,
      }}
    />
  );
};

const PhoneShot = ({
  image,
  accent,
  width,
  top,
  left,
  opacity,
  rotate,
  scale = 1,
  compact = false,
}: {
  image: string;
  accent: string;
  width: number;
  top: number;
  left: number;
  opacity: number;
  rotate: number;
  scale?: number;
  compact?: boolean;
}) => {
  const frame = useCurrentFrame();
  const shine = interpolate(frame % 120, [0, 45, 120], [-220, 680, 680], clamp);
  const radius = compact ? 58 : 72;

  return (
    <div
      style={{
        position: "absolute",
        top,
        left,
        width,
        borderRadius: radius,
        padding: compact ? 12 : 14,
        background: "#0A0A0A",
        boxShadow: `0 36px 110px rgba(0,0,0,0.22), 0 0 0 8px ${accent}18`,
        opacity,
        transform: `rotate(${rotate}deg) scale(${scale})`,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "relative",
          overflow: "hidden",
          borderRadius: radius - 14,
          background: "#FFFFFF",
        }}
      >
        <Img
          src={staticFile(image)}
          style={{
            width: "100%",
            display: "block",
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 0,
            bottom: 0,
            left: shine,
            width: 120,
            transform: "skewX(-18deg)",
            background:
              "linear-gradient(90deg, rgba(255,255,255,0), rgba(255,255,255,0.35), rgba(255,255,255,0))",
            opacity: 0.75,
          }}
        />
      </div>
    </div>
  );
};

const FinalCard = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const start = sec(26.1, fps);
  const enter = interpolate(frame, [start, start + sec(0.8, fps)], [0, 1], {
    ...clamp,
    easing: softEase,
  });
  const pulse = interpolate(frame, [start + sec(1.2, fps), sec(30, fps)], [0, 1], {
    ...clamp,
    easing: editorialEase,
  });

  return (
    <AbsoluteFill
      style={{
        opacity: enter,
        transform: `translateY(${interpolate(enter, [0, 1], [46, 0])}px)`,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 190,
          left: 86,
          right: 86,
          bottom: 190,
          borderRadius: 72,
          background: "rgba(255,255,255,0.78)",
          border: "1px solid rgba(0,0,0,0.06)",
          boxShadow: "0 34px 120px rgba(32,32,32,0.12)",
        }}
      />
      <Img
        src={staticFile("lifelify-icon.png")}
        style={{
          position: "absolute",
          top: 310,
          left: 380,
          width: 320,
          height: 320,
          borderRadius: 72,
          boxShadow: "0 35px 100px rgba(0,0,0,0.24)",
          transform: `scale(${1 + pulse * 0.03})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 690,
          left: 90,
          right: 90,
          textAlign: "center",
          fontSize: 92,
          fontWeight: 950,
          letterSpacing: 0,
        }}
      >
        lifelify
      </div>
      <div
        style={{
          position: "absolute",
          top: 815,
          left: 110,
          right: 110,
          textAlign: "center",
          fontSize: 42,
          lineHeight: 1.35,
          fontWeight: 820,
          color: "#333333",
        }}
      >
        日記・予定・ToDo・習慣・健康メモを
        <br />
        ひとつにまとめるライフログ
      </div>
      <div
        style={{
          position: "absolute",
          top: 1070,
          left: 210,
          right: 210,
          height: 104,
          borderRadius: 999,
          background: "#0A84FF",
          color: "#FFFFFF",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 38,
          fontWeight: 900,
          boxShadow: "0 24px 70px rgba(10,132,255,0.30)",
        }}
      >
        App Storeで公開中
      </div>
      <div
        style={{
          position: "absolute",
          top: 1245,
          left: 130,
          right: 130,
          textAlign: "center",
          fontSize: 30,
          lineHeight: 1.5,
          fontWeight: 720,
          color: "#5C5C62",
        }}
      >
        毎日を整える小さな記録帳。
        <br />
        TikTok / Reels 用 30秒版
      </div>
    </AbsoluteFill>
  );
};

const ProgressPill = ({ progress }: { progress: number }) => {
  return (
    <div
      style={{
        position: "absolute",
        left: 120,
        right: 120,
        bottom: 86,
        height: 12,
        borderRadius: 999,
        background: "rgba(0,0,0,0.08)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          width: `${Math.max(0, Math.min(1, progress)) * 100}%`,
          height: "100%",
          background:
            "linear-gradient(90deg, #0A84FF 0%, #FF8A1F 42%, #24B45A 100%)",
        }}
      />
    </div>
  );
};
