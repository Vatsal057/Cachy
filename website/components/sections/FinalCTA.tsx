import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { CachyGlyph } from "@/components/brand/Logo";
import { CACHY } from "@/lib/constants";

export function FinalCTA() {
  return (
    <section className="relative overflow-hidden py-32 sm:py-40">
      <div className="pointer-events-none absolute left-1/2 top-1/2 h-[360px] w-[720px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-sage/[0.08] blur-[130px]" />
      <Container className="relative">
        <Reveal className="mx-auto flex max-w-2xl flex-col items-center text-center">
          <CachyGlyph size={52} />
          <h2 className="mt-8 text-display text-[clamp(2.4rem,6vw,4rem)] font-semibold text-ink">
            Stop saving. Start remembering.
          </h2>
          <p className="mt-5 max-w-md text-lg leading-relaxed text-muted">
            {CACHY.tagline} Cachy keeps the good stuff so you don&apos;t have to.
          </p>
          <div className="mt-9">
            <Button href={CACHY.download.apk} external size="lg">
              Get Cachy
              <ArrowRight size={18} />
            </Button>
          </div>
          <p className="mt-4 font-mono text-xs text-muted">
            Free · Android APK · no app store needed
          </p>
        </Reveal>
      </Container>
    </section>
  );
}
