import { Hero } from '@/components/landing/Hero'
import { HowItWorks } from '@/components/landing/HowItWorks'
import { LandingFooter } from '@/components/landing/LandingFooter'
import { LandingNav } from '@/components/landing/LandingNav'
import { SmartContractSection } from '@/components/landing/SmartContractSection'
import { WhyPostQuantum } from '@/components/landing/WhyPostQuantum'
import { useDocumentTitle } from '@/lib/router'

export default function Landing() {
  useDocumentTitle('ArcStream-PQ | USDC Milestone Escrow on Arc')
  return (
    <div className="min-h-dvh neu-canvas font-sans antialiased text-zinc-200 selection:bg-neonLime selection:text-black">
      <LandingNav />
      <main>
        <Hero />
        <HowItWorks />
        <WhyPostQuantum />
        <SmartContractSection />
      </main>
      <LandingFooter />
    </div>
  )
}
