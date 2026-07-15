import { KeyRound, EyeOff, Hand } from "lucide-react";
import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";

const POINTS = [
  { icon: Hand, text: "You choose what to save." },
  { icon: EyeOff, text: "No data collected beyond what you send." },
  { icon: KeyRound, text: "No cross-site tracking. No ad profiles." },
];

export function Privacy() {
  return (
    <section id="privacy" className="scroll-mt-20 py-24 sm:py-32">
      <Container>
        <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
          <Reveal>
            <h2 className="text-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold text-ink">
              Your knowledge
              <br />
              belongs to you.
            </h2>
          </Reveal>
          <Reveal delay={0.08}>
            <ul className="flex flex-col gap-4">
              {POINTS.map((p) => (
                <li
                  key={p.text}
                  className="flex items-center gap-4 border-b border-ink/[0.08] pb-4 last:border-0"
                >
                  <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-sage/12 text-sage">
                    <p.icon size={18} />
                  </span>
                  <span className="text-lg text-ink/90">{p.text}</span>
                </li>
              ))}
            </ul>
          </Reveal>
        </div>
      </Container>
    </section>
  );
}
