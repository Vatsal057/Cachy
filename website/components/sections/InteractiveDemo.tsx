"use client";

import { useRef, useState } from "react";
import { AnimatePresence, motion, useMotionValueEvent, useScroll } from "framer-motion";
import {
  Smartphone,
  Send,
  Loader,
  Sparkles,
  Search,
  Link2,
  CalendarCheck,
  Check,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Container } from "@/components/ui/Container";
import { CACHY } from "@/lib/constants";
import { EASE_OUT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

type Beat = { icon: LucideIcon; title: string; note: string };

const BEATS: Beat[] = [
  { icon: Smartphone, title: "You spot something good", note: "A reel, a video, a page worth keeping." },
  { icon: Send, title: "Send it to Cachy", note: `A share, or a DM to ${CACHY.handle}.` },
  { icon: Loader, title: "Cachy reads it", note: "Watches, transcribes, structures." },
  { icon: Sparkles, title: "A knowledge card appears", note: "Summary, key ideas, what to do next." },
  { icon: Search, title: "Search by meaning", note: "Ask for the idea, not the filename." },
  { icon: Link2, title: "Related ideas surface", note: "One card leads to the next." },
  { icon: CalendarCheck, title: "Act on it", note: "Reminders and to-dos, one tap out." },
  { icon: Check, title: "Done", note: "Kept for good. You never opened the app." },
];

export function InteractiveDemo() {
  const reduced = usePrefersReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);

  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start start", "end end"],
  });

  useMotionValueEvent(scrollYProgress, "change", (v) => {
    const idx = Math.min(BEATS.length - 1, Math.floor(v * BEATS.length));
    setActive(idx);
  });

  if (reduced) return <StaticDemo />;

  return (
    <section id="demo" className="scroll-mt-20">
      <Container>
        <div className="mx-auto max-w-2xl pt-24 text-center sm:pt-32">
          <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
            Watch it happen.
          </h2>
          <p className="mx-auto mt-5 max-w-prose text-lg leading-relaxed text-muted">
            Scroll through the whole thing — from a link you&apos;d lose to
            knowledge you&apos;ll keep.
          </p>
        </div>
      </Container>

      {/* tall scroll track with a pinned stage */}
      <div ref={ref} className="relative h-[500vh]">
        <div className="sticky top-0 flex h-screen items-center">
          <Container className="grid w-full items-center gap-10 lg:grid-cols-[0.9fr_1.1fr]">
            {/* step list */}
            <ol className="hidden flex-col gap-1 lg:flex">
              {BEATS.map((beat, idx) => {
                const on = idx === active;
                const done = idx < active;
                return (
                  <li
                    key={beat.title}
                    className="flex items-center gap-4 rounded-2xl px-4 py-3 transition-colors duration-300"
                    style={{ background: on ? "rgba(150,168,133,0.08)" : "transparent" }}
                  >
                    <span
                      className={`grid h-9 w-9 shrink-0 place-items-center rounded-full border transition-colors duration-300 ${
                        on
                          ? "border-sage bg-sage text-ground"
                          : done
                            ? "border-sage/40 text-sage"
                            : "border-ink/15 text-muted"
                      }`}
                    >
                      <beat.icon size={16} />
                    </span>
                    <div>
                      <p className={`font-medium transition-colors duration-300 ${on ? "text-ink" : "text-muted"}`}>
                        {beat.title}
                      </p>
                    </div>
                  </li>
                );
              })}
            </ol>

            {/* stage */}
            <div className="relative">
              <DemoStage active={active} />
              {/* mobile progress dots */}
              <div className="mt-6 flex justify-center gap-1.5 lg:hidden">
                {BEATS.map((b, idx) => (
                  <span
                    key={b.title}
                    className={`h-1.5 rounded-full transition-all duration-300 ${idx === active ? "w-5 bg-sage" : "w-1.5 bg-ink/20"}`}
                  />
                ))}
              </div>
            </div>
          </Container>
        </div>
      </div>
    </section>
  );
}

function DemoStage({ active }: { active: number }) {
  const beat = BEATS[active];
  const Icon = beat.icon;
  return (
    <div className="relative mx-auto aspect-square w-full max-w-md overflow-hidden rounded-4xl border border-ink/10 bg-raised shadow-lift grain">
      <div className="absolute left-5 top-5 font-mono text-xs uppercase tracking-wider text-sage">
        {String(active + 1).padStart(2, "0")} / {String(BEATS.length).padStart(2, "0")}
      </div>
      <AnimatePresence mode="wait">
        <motion.div
          key={active}
          initial={{ opacity: 0, y: 24, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -24, scale: 0.98 }}
          transition={{ duration: 0.45, ease: EASE_OUT }}
          className="flex h-full w-full flex-col items-center justify-center gap-6 px-10 text-center"
        >
          <span className="grid h-20 w-20 place-items-center rounded-3xl bg-sage/15 text-sage">
            <Icon size={38} />
          </span>
          <div>
            <h3 className="text-display text-3xl font-semibold text-ink">
              {beat.title}
            </h3>
            <p className="mt-3 text-base leading-relaxed text-muted">{beat.note}</p>
          </div>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

/** Reduced-motion: all eight beats presented statically. */
function StaticDemo() {
  return (
    <section id="demo" className="scroll-mt-20 py-24 sm:py-32">
      <Container>
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
            Watch it happen.
          </h2>
          <p className="mx-auto mt-5 max-w-prose text-lg leading-relaxed text-muted">
            From a link you&apos;d lose to knowledge you&apos;ll keep.
          </p>
        </div>
        <ol className="mx-auto mt-14 grid max-w-4xl gap-4 sm:grid-cols-2">
          {BEATS.map((beat, idx) => (
            <li
              key={beat.title}
              className="flex items-start gap-4 rounded-2xl border border-ink/10 bg-raised p-5"
            >
              <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-sage/15 text-sage">
                <beat.icon size={20} />
              </span>
              <div>
                <p className="font-mono text-xs text-sage">
                  {String(idx + 1).padStart(2, "0")}
                </p>
                <h3 className="mt-0.5 font-medium text-ink">{beat.title}</h3>
                <p className="mt-1 text-sm leading-relaxed text-muted">{beat.note}</p>
              </div>
            </li>
          ))}
        </ol>
      </Container>
    </section>
  );
}
