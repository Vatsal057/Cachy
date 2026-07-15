import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { FeatureVisual } from "@/components/sections/FeatureVisual";
import { FEATURES } from "@/lib/constants";

export function Features() {
  return (
    <section id="features" className="scroll-mt-20 py-24 sm:py-32">
      <Container>
        <Reveal className="max-w-2xl">
          <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
            Built to be remembered.
          </h2>
        </Reveal>

        <div className="mt-16 flex flex-col gap-20 sm:gap-28">
          {FEATURES.map((feature, idx) => {
            const mediaFirst = idx % 2 === 0;
            return (
              <div
                key={feature.key}
                className="grid items-center gap-8 lg:grid-cols-2 lg:gap-16"
              >
                <Reveal
                  className={mediaFirst ? "lg:order-1" : "lg:order-2"}
                  y={28}
                >
                  <FeatureVisual variant={feature.key} />
                </Reveal>

                <Reveal
                  delay={0.08}
                  className={mediaFirst ? "lg:order-2" : "lg:order-1"}
                >
                  <h3 className="text-display text-[clamp(1.75rem,3.5vw,2.5rem)] font-semibold text-ink">
                    {feature.title}
                  </h3>
                  <p className="mt-4 max-w-md text-lg leading-relaxed text-muted">
                    {feature.body}
                  </p>
                </Reveal>
              </div>
            );
          })}
        </div>
      </Container>
    </section>
  );
}
