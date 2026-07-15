"use client";

import { motion } from "framer-motion";
import { ArrowRight, Play } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";
import { PhoneMockup } from "@/components/ui/PhoneMockup";
import { CACHY } from "@/lib/constants";
import { EASE_OUT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

export function Hero() {
  const reduced = usePrefersReducedMotion();

  const item = {
    hidden: { opacity: reduced ? 1 : 0, y: reduced ? 0 : 20 },
    show: (d = 0) => ({
      opacity: 1,
      y: 0,
      transition: { duration: 0.8, ease: EASE_OUT, delay: reduced ? 0 : d },
    }),
  };

  return (
    <section
      id="top"
      className="grain relative overflow-hidden pb-20 pt-32 sm:pt-40"
    >
      {/* one soft, low-chroma glow — not neon, not a gradient wash */}
      <div className="pointer-events-none absolute left-1/2 top-24 h-[420px] w-[820px] -translate-x-1/2 rounded-full bg-sage/[0.07] blur-[120px]" />

      <Container className="relative">
        <div className="grid items-center gap-14 lg:grid-cols-[1.05fr_0.95fr]">
          <div className="max-w-xl">
            <motion.p
              custom={0}
              variants={item}
              initial="hidden"
              animate="show"
              className="mb-6 inline-flex items-center gap-2 rounded-full border border-ink/10 bg-raised/60 px-3.5 py-1.5 font-mono text-[11px] uppercase tracking-wider text-muted"
            >
              <span className="h-1.5 w-1.5 rounded-full bg-sage" />
              {CACHY.tagline}
            </motion.p>

            <motion.h1
              custom={0.08}
              variants={item}
              initial="hidden"
              animate="show"
              className="text-display text-[clamp(2.6rem,7vw,4.5rem)] font-semibold text-ink"
            >
              Don&apos;t save content.
              <br />
              <span className="text-sage">Catch knowledge.</span>
            </motion.h1>

            <motion.p
              custom={0.16}
              variants={item}
              initial="hidden"
              animate="show"
              className="mt-6 max-w-md text-lg leading-relaxed text-muted"
            >
              You save things you never open again. Send it to Cachy instead —
              the easiest way is a DM to{" "}
              <span className="font-mono text-sm text-sage">{CACHY.handle}</span>{" "}
              on Instagram — and it&apos;s yours to find later.
            </motion.p>

            <motion.div
              custom={0.24}
              variants={item}
              initial="hidden"
              animate="show"
              className="mt-9 flex flex-wrap items-center gap-3"
            >
              <Button href={CACHY.download.apk} external size="lg">
                Get Cachy
                <ArrowRight size={18} />
              </Button>
              <Button href="#demo" variant="secondary" size="lg">
                <Play size={16} />
                Watch demo
              </Button>
            </motion.div>
          </div>

          <motion.div
            initial={{ opacity: reduced ? 1 : 0, y: reduced ? 0 : 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 1, ease: EASE_OUT, delay: reduced ? 0 : 0.2 }}
          >
            <PhoneMockup />
          </motion.div>
        </div>
      </Container>
    </section>
  );
}
