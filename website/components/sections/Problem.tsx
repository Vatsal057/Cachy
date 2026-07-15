"use client";

import { useEffect, useRef, useState } from "react";
import { motion, useInView } from "framer-motion";
import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { EASE_OUT, VIEWPORT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

const TARGET = 3482;

export function Problem() {
  return (
    <section className="relative py-24 sm:py-32">
      <Container>
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal className="order-2 lg:order-1">
            <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
              You&apos;re saving everything.
              <br />
              <span className="text-muted">Remembering nothing.</span>
            </h2>
            <p className="mt-5 max-w-md text-lg leading-relaxed text-muted">
              Every save is a promise to your future self. Most of them become a
              graveyard you never walk back through.
            </p>
          </Reveal>

          <Reveal delay={0.1} className="order-1 lg:order-2">
            <StatCard />
          </Reveal>
        </div>
      </Container>
    </section>
  );
}

function StatCard() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, VIEWPORT);
  const reduced = usePrefersReducedMotion();
  const [count, setCount] = useState(reduced ? TARGET : 0);

  useEffect(() => {
    if (reduced || !inView) return;
    let raf = 0;
    const start = performance.now();
    const dur = 1400;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / dur);
      // ease-out
      const eased = 1 - Math.pow(1 - t, 4);
      setCount(Math.round(eased * TARGET));
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [inView, reduced]);

  return (
    <div
      ref={ref}
      className="relative overflow-hidden rounded-4xl border border-ink/10 bg-raised p-8 shadow-soft sm:p-10"
    >
      <div className="grain absolute inset-0 opacity-60" />
      <div className="relative">
        <div className="flex items-baseline gap-3">
          <span className="font-mono text-sm uppercase tracking-wider text-muted">
            Saved
          </span>
        </div>
        <div
          className="mt-1 text-display text-[clamp(3.5rem,10vw,6rem)] font-semibold tabular-nums leading-none text-ink"
          aria-label={`${TARGET} items saved`}
        >
          {count.toLocaleString("en-US")}
        </div>

        <div className="mt-8 h-px w-full bg-ink/[0.08]" />

        <div className="mt-6 flex items-center justify-between">
          <span className="font-mono text-sm uppercase tracking-wider text-muted">
            Last opened
          </span>
          <motion.span
            initial={reduced ? undefined : { opacity: 0 }}
            animate={inView || reduced ? { opacity: 1 } : undefined}
            transition={{ delay: 0.9, duration: 0.5, ease: EASE_OUT }}
            className="font-display text-2xl font-semibold text-sage sm:text-3xl"
          >
            Never
          </motion.span>
        </div>
      </div>
    </div>
  );
}
