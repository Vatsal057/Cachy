"use client";

import { motion } from "framer-motion";
import type { ReactNode } from "react";
import { EASE_OUT, VIEWPORT } from "@/lib/motion";
import { usePrefersReducedMotion } from "@/lib/useReducedMotion";

/**
 * Scroll reveal that degrades to a fully-visible static state under
 * prefers-reduced-motion. Fires once, ~25% into view.
 */
export function Reveal({
  children,
  delay = 0,
  y = 24,
  className,
  as = "div",
}: {
  children: ReactNode;
  delay?: number;
  y?: number;
  className?: string;
  as?: "div" | "li" | "section" | "span";
}) {
  const reduced = usePrefersReducedMotion();
  const MotionTag = motion[as];

  if (reduced) {
    const Tag = as;
    return <Tag className={className}>{children}</Tag>;
  }

  return (
    <MotionTag
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={VIEWPORT}
      transition={{ duration: 0.7, ease: EASE_OUT, delay }}
    >
      {children}
    </MotionTag>
  );
}
