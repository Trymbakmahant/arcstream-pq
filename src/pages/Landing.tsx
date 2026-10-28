import { Hero } from '@/components/landing/Hero'
import { HowItWorks } from '@/components/landing/HowItWorks'
import { LandingFooter } from '@/components/landing/LandingFooter'
import { LandingNav } from '@/components/landing/LandingNav'
import { WhyPostQuantum } from '@/components/landing/WhyPostQuantum'
import { useDocumentTitle } from '@/lib/router'

export default function Landing() {
  useDocumentTitle('ArcStream-PQ | USDC Milestone Escrow on Arc')
  return (
    <div className="min-h-dvh bg-brandMain">
      <LandingNav />
      <main>
        <Hero />
        <HowItWorks />
        <WhyPostQuantum />
      </main>
      <LandingFooter />
    </div>
  )
}
