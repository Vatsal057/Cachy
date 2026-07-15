"use client";

import { motion } from "framer-motion";
import { ChefHat, ShoppingCart, CalendarDays, Activity } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { EASE_OUT, VIEWPORT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

const NODES: { label: string; icon: LucideIcon }[] = [
  { label: "Recipe", icon: ChefHat },
  { label: "Shopping List", icon: ShoppingCart },
  { label: "Meal Prep", icon: CalendarDays },
  { label: "Nutrition", icon: Activity },
];

export function Solution() {
  const reduced = usePrefersReducedMotion();

  return (
    <section className="relative py-24 sm:py-32">
      <Container>
        <Reveal className="mx-auto max-w-2xl text-center">
          <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
            One thing you saved,
            <br />
            <span className="text-sage">connected to the next.</span>
          </h2>
          <p className="mx-auto mt-5 max-w-prose text-lg leading-relaxed text-muted">
            Cachy links related ideas on its own. Everything you send becomes
            searchable, connected, and actually useful.
          </p>
        </Reveal>

        <motion.ul
          initial="hidden"
          whileInView="show"
          viewport={VIEWPORT}
          variants={{
            hidden: {},
            show: { transition: { staggerChildren: reduced ? 0 : 0.18 } },
          }}
          className="mx-auto mt-16 flex max-w-4xl flex-col items-stretch gap-0 lg:flex-row lg:items-center lg:justify-center"
        >
          {NODES.map((node, idx) => (
            <li key={node.label} className="contents">
              <motion.div
                variants={{
                  hidden: { opacity: 0, y: 18 },
                  show: {
                    opacity: 1,
                    y: 0,
                    transition: { duration: 0.55, ease: EASE_OUT },
                  },
                }}
                className="flex items-center gap-4 rounded-2xl border border-ink/10 bg-raised px-5 py-4 shadow-soft lg:flex-col lg:gap-3 lg:px-6 lg:py-6 lg:text-center"
              >
                <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-sage/15 text-sage">
                  <node.icon size={20} />
                </span>
                <span className="font-medium text-ink">{node.label}</span>
              </motion.div>

              {idx < NODES.length - 1 && <Connector index={idx} reduced={reduced} />}
            </li>
          ))}
        </motion.ul>
      </Container>
    </section>
  );
}

function Connector({ index, reduced }: { index: number; reduced: boolean }) {
  return (
    <motion.span
      aria-hidden="true"
      variants={{
        hidden: { scaleX: reduced ? 1 : 0, scaleY: reduced ? 1 : 0, opacity: reduced ? 1 : 0 },
        show: {
          scaleX: 1,
          scaleY: 1,
          opacity: 1,
          transition: { duration: 0.4, ease: EASE_OUT, delay: 0.1 + index * 0.18 },
        },
      }}
      className="mx-auto my-1 block h-6 w-px origin-top bg-gradient-to-b from-sage/50 to-sage/10 lg:my-0 lg:h-px lg:w-10 lg:origin-left lg:bg-gradient-to-r"
    />
  );
}
