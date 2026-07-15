import { Wordmark } from "@/components/brand/Logo";
import { Container } from "@/components/ui/Container";
import { CACHY } from "@/lib/constants";

export function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="border-t border-ink/[0.08] py-12">
      <Container className="flex flex-col items-center justify-between gap-6 sm:flex-row">
        <Wordmark size={18} />

        <nav aria-label="Footer" className="flex items-center gap-7 text-sm">
          <a href="#privacy" className="text-muted transition-colors hover:text-ink">
            Privacy
          </a>
          <a href={`mailto:${CACHY.email}`} className="text-muted transition-colors hover:text-ink">
            Email
          </a>
        </nav>

        <p className="font-mono text-xs text-muted">
          © {year} Cachy
        </p>
      </Container>
    </footer>
  );
}
