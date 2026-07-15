"use client";

import { motion } from "framer-motion";
import { Send, Sparkles, Search } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { HOW_IT_WORKS } from "@/lib/constants";
import { EASE_OUT, VIEWPORT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

const ICONS: Record<string, LucideIcon> = {
  catch: Send,
  understand: Sparkles,
  remember: Search,
};

export function HowItWorks() {
  const reduced = usePrefersReducedMotion();

  return (
    <section className="relative py-24 sm:py-32">
      <Container>
        <Reveal className="max-w-2xl">
          <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
            How it works
          </h2>
          <p className="mt-5 max-w-prose text-lg leading-relaxed text-muted">
            Three steps. You only ever do the first one.
          </p>
        </Reveal>

        <motion.ol
          initial="hidden"
          whileInView="show"
          viewport={VIEWPORT}
          variants={{
            hidden: {},
            show: { transition: { staggerChildren: reduced ? 0 : 0.14 } },
          }}
          className="mt-14 grid gap-5 md:grid-cols-3"
        >
          {HOW_IT_WORKS.map((step, idx) => {
            const Icon = ICONS[step.key];
            return (
              <motion.li
                key={step.key}
                variants={{
                  hidden: { opacity: 0, y: 22 },
                  show: {
                    opacity: 1,
                    y: 0,
                    transition: { duration: 0.6, ease: EASE_OUT },
                  },
                }}
                className="group relative flex flex-col rounded-4xl border border-ink/10 bg-raised p-7 transition-colors duration-300 hover:border-sage/30"
              >
                <div className="flex items-center justify-between">
                  <span className="grid h-12 w-12 place-items-center rounded-2xl bg-sage/15 text-sage transition-transform duration-300 ease-out-quint group-hover:-translate-y-0.5">
                    <Icon size={22} />
                  </span>
                  <span className="font-mono text-sm text-ink/25">
                    0{idx + 1}
                  </span>
                </div>
                <h3 className="mt-6 font-display text-2xl font-semibold text-ink">
                  {step.title}
                </h3>
                <p className="mt-2.5 leading-relaxed text-muted">{step.body}</p>
              </motion.li>
            );
          })}
        </motion.ol>
      </Container>
    </section>
  );
}
