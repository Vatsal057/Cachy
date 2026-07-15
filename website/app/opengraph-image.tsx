import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "Cachy — Send it. Forget about it.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#181818",
          padding: "80px",
          fontFamily: "Georgia, serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <svg width="56" height="56" viewBox="0 0 32 32" fill="none">
            <path
              d="M5.76 9.6 L5.76 21.12 A5.12 5.12 0 0 0 10.88 26.24 L21.12 26.24 A5.12 5.12 0 0 0 26.24 21.12 L26.24 9.6"
              stroke="#96A885"
              strokeWidth="4.16"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <rect x="11.2" y="11.2" width="9.6" height="9.6" rx="3" fill="#96A885" fillOpacity="0.55" />
          </svg>
          <span style={{ color: "#EDE8DF", fontSize: 40, fontWeight: 600, letterSpacing: -1 }}>
            cachy
          </span>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
          <div
            style={{
              color: "#EDE8DF",
              fontSize: 84,
              fontWeight: 600,
              letterSpacing: -3,
              lineHeight: 1.02,
              maxWidth: 900,
            }}
          >
            Don&apos;t save content. Catch knowledge.
          </div>
          <div style={{ color: "#96A885", fontSize: 34, fontFamily: "monospace" }}>
            Send it. Forget about it.
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
