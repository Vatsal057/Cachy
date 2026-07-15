import { Container } from "@/components/ui/Container";
import { Reveal } from "@/components/ui/Reveal";
import { SOURCES } from "@/lib/constants";

export function SourceRow() {
  return (
    <section aria-label="Where you can send content from" className="py-10">
      <Container>
        <Reveal className="flex flex-col items-center gap-6">
          <p className="text-center text-sm text-muted">
            Send it from anywhere. Instagram is just the easiest.
          </p>
          <ul className="flex flex-wrap items-center justify-center gap-x-7 gap-y-3 sm:gap-x-10">
            {SOURCES.map((source) => (
              <li
                key={source}
                className="font-mono text-sm text-ink/55 transition-colors duration-200 hover:text-ink/85"
              >
                {source}
              </li>
            ))}
          </ul>
        </Reveal>
      </Container>
    </section>
  );
}
