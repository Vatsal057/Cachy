import { Navbar } from "@/components/sections/Navbar";
import { Hero } from "@/components/sections/Hero";
import { SourceRow } from "@/components/sections/SourceRow";
import { Problem } from "@/components/sections/Problem";
import { Solution } from "@/components/sections/Solution";
import { HowItWorks } from "@/components/sections/HowItWorks";
import { Features } from "@/components/sections/Features";
import { InteractiveDemo } from "@/components/sections/InteractiveDemo";
import { Privacy } from "@/components/sections/Privacy";
import { FAQ } from "@/components/sections/FAQ";
import { FinalCTA } from "@/components/sections/FinalCTA";
import { Footer } from "@/components/sections/Footer";

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <SourceRow />
        <Problem />
        <Solution />
        <HowItWorks />
        <Features />
        <InteractiveDemo />
        <Privacy />
        <FAQ />
        <FinalCTA />
      </main>
      <Footer />
    </>
  );
}
