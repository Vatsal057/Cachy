import type { ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";

const base =
  "inline-flex items-center justify-center gap-2 rounded-full font-medium " +
  "transition-[transform,background-color,border-color,color] duration-200 ease-out-quint " +
  "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[3px] " +
  "focus-visible:outline-sage active:scale-[0.98] select-none";

const sizes = {
  md: "h-11 px-5 text-[15px]",
  lg: "h-[52px] px-7 text-base",
};

const variants: Record<Variant, string> = {
  primary:
    "bg-sage text-ground hover:bg-sage-strong shadow-soft hover:shadow-lift",
  secondary:
    "border border-ink/15 bg-transparent text-ink hover:bg-ink/[0.06] hover:border-ink/25",
  ghost: "text-muted hover:text-ink",
};

export function Button({
  children,
  href,
  variant = "primary",
  size = "md",
  className = "",
  external,
  ariaLabel,
}: {
  children: ReactNode;
  href: string;
  variant?: Variant;
  size?: "md" | "lg";
  className?: string;
  external?: boolean;
  ariaLabel?: string;
}) {
  const cls = `${base} ${sizes[size]} ${variants[variant]} ${className}`;
  const rel = external ? "noopener noreferrer" : undefined;
  const target = external ? "_blank" : undefined;
  return (
    <a
      href={href}
      target={target}
      rel={rel}
      aria-label={ariaLabel}
      className={cls}
    >
      {children}
    </a>
  );
}
