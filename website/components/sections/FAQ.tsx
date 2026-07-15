"use client";

import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Plus } from "lucide-react";
import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { FAQS } from "@/lib/constants";
import { EASE_OUT } from "@/lib/motion";

export function FAQ() {
  const [open, setOpen] = useState<number | null>(null);

  return (
    <section id="faq" className="scroll-mt-20 py-24 sm:py-32">
      <Container>
        <div className="grid gap-12 lg:grid-cols-[0.8fr_1.2fr]">
          <Reveal>
            <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
              Questions,
              <br />
              answered.
            </h2>
          </Reveal>

          <Reveal delay={0.08}>
            <ul className="divide-y divide-ink/[0.08] border-y border-ink/[0.08]">
              {FAQS.map((faq, idx) => {
                const isOpen = open === idx;
                const panelId = `faq-panel-${idx}`;
                const btnId = `faq-btn-${idx}`;
                return (
                  <li key={faq.q}>
                    <h3>
                      <button
                        id={btnId}
                        type="button"
                        aria-expanded={isOpen}
                        aria-controls={panelId}
                        onClick={() => setOpen(isOpen ? null : idx)}
                        className="flex w-full items-center justify-between gap-4 py-5 text-left"
                      >
                        <span className="text-lg font-medium text-ink">
                          {faq.q}
                        </span>
                        <motion.span
                          animate={{ rotate: isOpen ? 45 : 0 }}
                          transition={{ duration: 0.25, ease: EASE_OUT }}
                          className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-ink/15 text-muted"
                        >
                          <Plus size={16} />
                        </motion.span>
                      </button>
                    </h3>
                    <AnimatePresence initial={false}>
                      {isOpen && (
                        <motion.div
                          id={panelId}
                          role="region"
                          aria-labelledby={btnId}
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: "auto", opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          transition={{ duration: 0.32, ease: EASE_OUT }}
                          className="overflow-hidden"
                        >
                          <p className="max-w-prose pb-6 pr-10 leading-relaxed text-muted">
                            {faq.a}
                          </p>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </li>
                );
              })}
            </ul>
          </Reveal>
        </div>
      </Container>
    </section>
  );
}
