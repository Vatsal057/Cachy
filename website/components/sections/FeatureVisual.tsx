"use client";

import { motion } from "framer-motion";
import { Search, Link2, Layers, FileText, Youtube, Newspaper } from "lucide-react";
import { CachyGlyph } from "@/components/brand/Logo";
import { EASE_OUT, VIEWPORT } from "@/lib/motion";

const frame =
  "relative aspect-[4/3] w-full overflow-hidden rounded-4xl border border-ink/10 bg-raised shadow-soft grain";

/** Distinct visual per feature — no repeated card grid. */
export function FeatureVisual({ variant }: { variant: string }) {
  if (variant === "send") return <SendVisual />;
  if (variant === "search") return <SearchVisual />;
  if (variant === "connect") return <ConnectVisual />;
  return <KeepVisual />;
}

function SendVisual() {
  const chips = [
    { icon: FileText, label: "PDF" },
    { icon: Youtube, label: "YouTube" },
    { icon: Newspaper, label: "Article" },
  ];
  return (
    <div className={frame}>
      <div className="absolute inset-0 flex items-center justify-between px-8 sm:px-12">
        <div className="flex flex-col gap-3">
          {chips.map((c, i) => (
            <motion.div
              key={c.label}
              initial={{ opacity: 0, x: -16 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={VIEWPORT}
              transition={{ delay: i * 0.12, duration: 0.5, ease: EASE_OUT }}
              className="flex items-center gap-2.5 rounded-full border border-ink/10 bg-ground/70 px-3.5 py-2"
            >
              <c.icon size={15} className="text-muted" />
              <span className="text-xs text-ink/80">{c.label}</span>
            </motion.div>
          ))}
        </div>
        <motion.div
          initial={{ scale: 0.85, opacity: 0 }}
          whileInView={{ scale: 1, opacity: 1 }}
          viewport={VIEWPORT}
          transition={{ delay: 0.3, duration: 0.6, ease: EASE_OUT }}
          className="grid h-20 w-20 place-items-center rounded-3xl bg-sage/15"
        >
          <CachyGlyph size={48} />
        </motion.div>
      </div>
    </div>
  );
}

function SearchVisual() {
  return (
    <div className={frame}>
      <div className="absolute inset-0 flex flex-col justify-center gap-3 px-8 sm:px-10">
        <div className="flex items-center gap-3 rounded-full border border-sage/30 bg-ground/70 px-4 py-3">
          <Search size={16} className="text-sage" />
          <span className="text-sm text-ink/80">
            that pasta trick I saw once
          </span>
        </div>
        {["Cacio e pepe, no cream", "Salt the water like the sea"].map(
          (r, i) => (
            <motion.div
              key={r}
              initial={{ opacity: 0, y: 10 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT}
              transition={{ delay: 0.25 + i * 0.14, duration: 0.5, ease: EASE_OUT }}
              className="flex items-center gap-3 rounded-2xl border border-ink/[0.06] bg-raised2 px-4 py-3"
            >
              <span className="h-1.5 w-1.5 rounded-full bg-sage" />
              <span className="text-sm text-ink/85">{r}</span>
            </motion.div>
          ),
        )}
      </div>
    </div>
  );
}

function ConnectVisual() {
  const nodes = [
    { x: 28, y: 32 },
    { x: 72, y: 26 },
    { x: 50, y: 58 },
    { x: 24, y: 74 },
    { x: 78, y: 70 },
  ];
  const edges = [
    [0, 2],
    [1, 2],
    [2, 3],
    [2, 4],
  ];
  return (
    <div className={frame}>
      <svg className="absolute inset-0 h-full w-full" viewBox="0 0 100 100" preserveAspectRatio="none">
        {edges.map(([a, b], i) => (
          <motion.line
            key={i}
            x1={nodes[a].x}
            y1={nodes[a].y}
            x2={nodes[b].x}
            y2={nodes[b].y}
            stroke="#96A885"
            strokeWidth={0.5}
            strokeOpacity={0.5}
            initial={{ pathLength: 0, opacity: 0 }}
            whileInView={{ pathLength: 1, opacity: 1 }}
            viewport={VIEWPORT}
            transition={{ delay: 0.2 + i * 0.12, duration: 0.6, ease: EASE_OUT }}
          />
        ))}
      </svg>
      {nodes.map((n, i) => (
        <motion.span
          key={i}
          initial={{ scale: 0, opacity: 0 }}
          whileInView={{ scale: 1, opacity: 1 }}
          viewport={VIEWPORT}
          transition={{ delay: i * 0.1, duration: 0.4, ease: EASE_OUT }}
          className="absolute rounded-full bg-sage"
          style={{
            left: `${n.x}%`,
            top: `${n.y}%`,
            width: i === 2 ? 16 : 10,
            height: i === 2 ? 16 : 10,
            transform: "translate(-50%,-50%)",
            boxShadow: i === 2 ? "0 0 0 6px rgba(150,168,133,0.14)" : undefined,
          }}
        />
      ))}
    </div>
  );
}

function KeepVisual() {
  return (
    <div className={frame}>
      <div className="absolute inset-0 grid place-items-center">
        <div className="relative h-40 w-52">
          {[0, 1, 2].map((k) => (
            <motion.div
              key={k}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT}
              transition={{ delay: k * 0.12, duration: 0.55, ease: EASE_OUT }}
              className="absolute left-1/2 w-48 rounded-2xl border border-ink/10 bg-raised2 p-4 shadow-soft"
              style={{
                top: k * 18,
                transform: `translateX(-50%) rotate(${(k - 1) * 3}deg)`,
                zIndex: 3 - k,
              }}
            >
              <div className="h-2 w-24 rounded-full bg-sage/40" />
              <div className="mt-2.5 h-1.5 w-full rounded-full bg-ink/10" />
              <div className="mt-1.5 h-1.5 w-2/3 rounded-full bg-ink/10" />
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
}
