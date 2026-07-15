"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  Check,
  FileText,
  Link2,
  ListChecks,
  Send,
  Sparkles,
} from "lucide-react";
import { CachyGlyph } from "@/components/brand/Logo";
import { CACHY } from "@/lib/constants";
import { EASE_OUT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

const STAGES = ["source", "share", "processing", "card"] as const;
type Stage = (typeof STAGES)[number];
const DURATIONS: Record<Stage, number> = {
  source: 2200,
  share: 1900,
  processing: 2000,
  card: 3400,
};

export function PhoneMockup() {
  const reduced = usePrefersReducedMotion();
  const [i, setI] = useState(0);
  const stage: Stage = reduced ? "card" : STAGES[i];

  useEffect(() => {
    if (reduced) return;
    const t = setTimeout(
      () => setI((v) => (v + 1) % STAGES.length),
      DURATIONS[STAGES[i]],
    );
    return () => clearTimeout(t);
  }, [i, reduced]);

  return (
    <div className="relative mx-auto w-[280px] sm:w-[300px]" aria-hidden="true">
      {/* soft floor shadow */}
      <div className="absolute -bottom-6 left-1/2 h-10 w-3/4 -translate-x-1/2 rounded-[50%] bg-black/40 blur-2xl" />

      <div className="relative aspect-[9/19] w-full rounded-[2.6rem] border border-ink/10 bg-raised p-3 shadow-lift">
        <div className="absolute left-1/2 top-4 z-10 h-1.5 w-16 -translate-x-1/2 rounded-full bg-ink/15" />
        <div className="grain relative h-full w-full overflow-hidden rounded-[2rem] bg-ground">
          <StageBadge stage={stage} />

          <div className="relative z-[1] flex h-full w-full items-center justify-center p-5">
            <AnimatePresence mode="wait">
              {stage === "source" && <SourceScreen key="source" />}
              {stage === "share" && <ShareScreen key="share" />}
              {stage === "processing" && <ProcessingScreen key="processing" />}
              {stage === "card" && <CardScreen key="card" />}
            </AnimatePresence>
          </div>
        </div>
      </div>

      {!reduced && (
        <div className="mt-5 flex justify-center gap-1.5">
          {STAGES.map((s, idx) => (
            <span
              key={s}
              className={`h-1.5 rounded-full transition-all duration-500 ${
                idx === i ? "w-6 bg-sage" : "w-1.5 bg-ink/20"
              }`}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function StageBadge({ stage }: { stage: Stage }) {
  const label = {
    source: "A reel you'd forget",
    share: "Send it to Cachy",
    processing: "Reading it…",
    card: "Kept for good",
  }[stage];
  return (
    <div className="absolute left-4 top-4 z-[2]">
      <AnimatePresence mode="wait">
        <motion.span
          key={label}
          initial={{ opacity: 0, y: -6 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 6 }}
          transition={{ duration: 0.3, ease: EASE_OUT }}
          className="font-mono text-[10px] uppercase tracking-wider text-muted"
        >
          {label}
        </motion.span>
      </AnimatePresence>
    </div>
  );
}

const screen = {
  initial: { opacity: 0, y: 14 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -14 },
  transition: { duration: 0.45, ease: EASE_OUT },
};

function SourceScreen() {
  return (
    <motion.div {...screen} className="w-full">
      <div className="overflow-hidden rounded-2xl border border-ink/10 bg-raised">
        <div className="flex items-center gap-2 px-3 py-2.5">
          <div className="h-6 w-6 rounded-full bg-sage/30" />
          <div className="h-2 w-20 rounded-full bg-ink/15" />
        </div>
        <div className="relative aspect-[4/5] w-full bg-gradient-to-b from-raised2 to-ground">
          <div className="absolute inset-0 grid place-items-center">
            <div className="h-0 w-0 border-y-[10px] border-l-[16px] border-y-transparent border-l-ink/40" />
          </div>
          <span className="absolute bottom-2 left-3 font-mono text-[9px] uppercase tracking-wide text-muted">
            Reel · 0:42
          </span>
        </div>
        <div className="space-y-1.5 px-3 py-2.5">
          <div className="h-2 w-full rounded-full bg-ink/12" />
          <div className="h-2 w-2/3 rounded-full bg-ink/10" />
        </div>
      </div>
    </motion.div>
  );
}

function ShareScreen() {
  return (
    <motion.div {...screen} className="w-full">
      <div className="rounded-2xl border border-ink/10 bg-raised p-4">
        <p className="mb-3 text-center text-xs text-muted">Share to</p>
        <div className="flex items-center gap-3 rounded-xl border border-sage/30 bg-sage/[0.08] p-3">
          <div className="grid h-10 w-10 place-items-center rounded-full bg-sage/20">
            <CachyGlyph size={22} />
          </div>
          <div className="flex-1">
            <p className="text-sm font-medium text-ink">Cachy</p>
            <p className="font-mono text-[11px] text-sage">{CACHY.handle}</p>
          </div>
          <motion.div
            initial={{ scale: 0.6, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.35, duration: 0.4, ease: EASE_OUT }}
            className="grid h-8 w-8 place-items-center rounded-full bg-sage text-ground"
          >
            <Send size={15} />
          </motion.div>
        </div>
        <div className="mt-3 grid grid-cols-4 gap-2 opacity-40">
          {Array.from({ length: 4 }).map((_, k) => (
            <div key={k} className="flex flex-col items-center gap-1.5">
              <div className="h-9 w-9 rounded-full bg-ink/10" />
              <div className="h-1.5 w-8 rounded-full bg-ink/10" />
            </div>
          ))}
        </div>
      </div>
    </motion.div>
  );
}

function ProcessingScreen() {
  return (
    <motion.div {...screen} className="flex w-full flex-col items-center gap-5">
      <div className="relative grid h-24 w-24 place-items-center">
        <motion.span
          className="absolute inset-0 rounded-full border border-sage/30"
          animate={{ scale: [1, 1.15, 1], opacity: [0.5, 0, 0.5] }}
          transition={{ duration: 2, repeat: Infinity, ease: "easeOut" }}
        />
        <ReelDropGlyph />
      </div>
      <div className="w-full space-y-2">
        {["Watching", "Transcribing", "Structuring"].map((step, k) => (
          <motion.div
            key={step}
            initial={{ opacity: 0.3 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.3 + k * 0.5, duration: 0.4 }}
            className="flex items-center gap-2"
          >
            <motion.span
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              transition={{ delay: 0.5 + k * 0.5, duration: 0.3, ease: EASE_OUT }}
              className="grid h-4 w-4 place-items-center rounded-full bg-sage/25 text-sage"
            >
              <Check size={10} />
            </motion.span>
            <span className="font-mono text-[11px] text-muted">{step}</span>
          </motion.div>
        ))}
      </div>
    </motion.div>
  );
}

function ReelDropGlyph() {
  return (
    <motion.div
      initial={{ y: -8 }}
      animate={{ y: 0 }}
      transition={{ duration: 1, repeat: Infinity, repeatType: "reverse", ease: EASE_OUT }}
    >
      <CachyGlyph size={64} />
    </motion.div>
  );
}

function CardScreen() {
  const rows = [
    { icon: Sparkles, text: "One-liner + TL;DR" },
    { icon: ListChecks, text: "3 steps to try" },
    { icon: Link2, text: "2 related cards" },
    { icon: FileText, text: "Source kept" },
  ];
  return (
    <motion.div {...screen} className="w-full">
      <div className="rounded-2xl border border-ink/10 bg-raised p-4 shadow-soft">
        <span className="font-mono text-[9px] uppercase tracking-wider text-sage">
          Knowledge card
        </span>
        <h4 className="mt-1.5 font-display text-lg font-semibold leading-tight text-ink">
          Cold brew, done right
        </h4>
        <p className="mt-1 text-xs leading-relaxed text-muted">
          Coarse grind, 1:8 ratio, steep 16 hours cold.
        </p>
        <div className="mt-3 space-y-2">
          {rows.map(({ icon: Icon, text }, k) => (
            <motion.div
              key={text}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.2 + k * 0.12, duration: 0.4, ease: EASE_OUT }}
              className="flex items-center gap-2.5 rounded-lg border border-ink/[0.06] bg-ground/60 px-2.5 py-2"
            >
              <Icon size={14} className="text-sage" />
              <span className="text-[11px] text-ink/90">{text}</span>
            </motion.div>
          ))}
        </div>
      </div>
    </motion.div>
  );
}
