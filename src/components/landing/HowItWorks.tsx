import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Fingerprint, PackageCheck, Vault } from 'lucide-react'

const STEPS = [
  {
    icon: Vault,
    title: 'Fund & Lock Escrow',
    body: 'Employers deposit USDC for specific milestones with clear deliverables. Funds are locked in the ArcStreamVault contract, not held by anyone.',
    points: ['One deposit covers every milestone', 'Each milestone has its own amount and scope', 'Optional Touch ID / Face ID lock chosen at creation'],
  },
  {
    icon: PackageCheck,
    title: 'Deliver & Submit Proof',
    body: 'Contractors build and submit verifiable deliverables: GitHub commits, IPFS hashes, or documentation links, recorded onchain with the milestone.',
    points: ['Proof is public and time-stamped', 'Submitted work blocks employer refunds', 'Employer reviews the scope and the proof side by side'],
  },
  {
    icon: Fingerprint,
    title: 'Biometric Touch ID Release',
    body: 'Employers review the work, approve it, and confirm the release with Touch ID or Face ID. The contract checks a Merkle proof of a one-time secret and pays the contractor directly.',
    points: ['Each one-time secret is used once', 'Contractors can also claim approved milestones themselves', 'Payout goes straight to the contractor wallet'],
  },
]

export function HowItWorks() {
  const [active, setActive] = useState(0)
  const step = STEPS[active]
  const Icon = step.icon

  return (
    <section id="how-it-works" className="scroll-mt-28 border-y border-brandHighlight/10 bg-brandSecondary/15">
      <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <p className="label-caps text-brandHighlight/70">How it works</p>
        <h2 className="display mt-2 text-balance text-3xl font-bold text-brandHighlight sm:text-4xl">
          Three steps from deposit to payout.
        </h2>

        <div className="mt-10 grid gap-6 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
          <div role="tablist" aria-label="How it works" className="space-y-3">
            {STEPS.map((s, i) => {
              const selected = i === active
              return (
                <button
                  key={s.title}
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  onClick={() => setActive(i)}
                  className={`flex min-h-16 w-full items-center gap-4 rounded-2xl border p-4 text-left transition-colors ${
                    selected
                      ? 'border-brandHighlight bg-brandHighlight text-brandMain'
                      : 'border-brandSecondary bg-brandMain text-brandHighlight hover:bg-brandSecondary/30'
                  }`}
                >
                  <span
                    className={`flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-bold ${
                      selected ? 'bg-brandSecondary text-brandHighlight' : 'bg-brandHighlight text-brandMain'
                    }`}
                  >
                    {i + 1}
                  </span>
                  <span className="display text-base font-bold">{s.title}</span>
                </button>
              )
            })}
          </div>

          <div className="relative min-h-72 overflow-hidden rounded-2xl border border-brandSecondary bg-brandMain p-6 sm:p-8">
            <AnimatePresence mode="wait">
              <motion.div
                key={active}
                role="tabpanel"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.2 }}
              >
                <span className="flex size-12 items-center justify-center rounded-xl bg-brandHighlight text-brandMain">
                  <Icon className="size-6" />
                </span>
                <h3 className="display mt-4 text-2xl font-bold text-brandHighlight">
                  Step {active + 1}: {step.title}
                </h3>
                <p className="mt-2 text-pretty text-brandHighlight/80">{step.body}</p>
                <ul className="mt-5 space-y-2">
                  {step.points.map((point) => (
                    <li key={point} className="flex items-start gap-2 text-sm text-brandHighlight">
                      <span className="mt-1.5 size-2 shrink-0 rounded-full bg-brandSecondary" />
                      {point}
                    </li>
                  ))}
                </ul>
              </motion.div>
            </AnimatePresence>
          </div>
        </div>
      </div>
    </section>
  )
}
