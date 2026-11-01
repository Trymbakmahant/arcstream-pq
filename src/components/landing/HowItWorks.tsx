import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Check } from 'lucide-react'

const STEP_DATA = [
  {
    stepNum: 1,
    tabTitle: 'Deposit & Stage Allocation',
    tabSubtitle: 'Escrow creation with multi-milestone splits.',
    badge: 'Stage 01 • Employer Deposit & Gas Split',
    title: 'Deposit & Stage Allocation',
    desc: 'Employer deposits USDC into the milestone contract on Arc. Gas is paid directly in native USDC with zero bridge delays and zero slippage.',
    paramLabel1: 'vaultContract:',
    param1: '0x464504fe41fe...',
    paramLabel2: 'stateMachine:',
    param2: 'State: INITIALIZED (EscrowLocked)',
    paramLabel3: 'depositedAmount:',
    param3: '100,000.000000 USDC',
    bullet1: 'Multi-milestone escrow support',
    bullet2: 'USDC-native gas settlement',
  },
  {
    stepNum: 2,
    tabTitle: 'Deliverable & Anti-Ghosting Lock',
    tabSubtitle: 'Proof of work hash submitted onchain.',
    badge: 'Stage 02 • Contractor Artifact Submission',
    title: 'Deliverable & Anti-Ghosting Lock',
    desc: 'Contractor submits milestone work artifacts directly onchain. Submission instantly freezes employer cancellation rights, protecting hours of labor.',
    paramLabel1: 'artifactCid:',
    param1: 'ipfs://bafybeigdyrzt...',
    paramLabel2: 'stateMachine:',
    param2: 'State: SUBMITTED (RefundFrozen)',
    paramLabel3: 'reviewCountdown:',
    param3: 'Review Window: 7 Days Remaining',
    bullet1: 'Instant unilateral refund block',
    bullet2: 'Review countdown timer initiated',
  },
  {
    stepNum: 3,
    tabTitle: 'Biometric Post-Quantum Release',
    tabSubtitle: 'SLH-DSA FIPS 205 biometric authorization.',
    badge: 'Stage 03 • Biometric Verification',
    title: 'Hardware Passkey SLH-DSA Signature',
    desc: 'When employer approves deliverable, their physical device activates Touch ID or Face ID. A dedicated Web Worker computes the post-quantum stateless hash signature bound to the escrow domain and milestone index.',
    paramLabel1: 'escrowId:',
    param1: '0x464504fe41fe...',
    paramLabel2: 'fipsScheme:',
    param2: 'SLH-DSA-SHA2-128s (FIPS 205)',
    paramLabel3: 'payoutAmount:',
    param3: '25,000.000000 USDC',
    bullet1: 'Replay-resistant domain salt tag',
    bullet2: 'Immediate noncustodial USDC transfer',
  },
]

export function HowItWorks() {
  const [activeTab, setActiveTab] = useState(2) // Default to Stage 03 as in the design
  const d = STEP_DATA[activeTab]

  return (
    <section className="py-24 px-6 bg-[#080b10] border-t border-white/5 relative" id="how-it-works">
      <div className="max-w-6xl mx-auto">
        <div className="text-center max-w-3xl mx-auto mb-16">
          <p className="font-mono text-xs uppercase tracking-widest text-neonLime font-bold">Lifecycle Walkthrough</p>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-white mt-2">Zero-Trust Escrow from Deposit to Release</h2>
          <p className="text-zinc-400 text-sm sm:text-base mt-3">Click through each phase to inspect cryptographic state transitions executed on Arc.</p>
        </div>

        {/* Interactive 3-Step Container */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
          {/* Left: Step Selection Tabs */}
          <div className="lg:col-span-5 space-y-4" role="tablist" aria-label="Lifecycle walkthrough stages">
            {STEP_DATA.map((item, index) => {
              const selected = index === activeTab
              return (
                <button
                  key={item.stepNum}
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  onClick={() => setActiveTab(index)}
                  className={`w-full text-left p-5 rounded-2xl transition-all border group ${
                    selected
                      ? 'tab-active'
                      : 'neu-panel border-white/5 hover:border-white/10'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <span
                      className={`size-8 rounded-lg neu-inset font-mono text-xs font-bold flex items-center justify-center transition-colors ${
                        selected
                          ? 'text-neonLime'
                          : 'text-zinc-400 group-hover:text-neonLime'
                      }`}
                    >
                      0{item.stepNum}
                    </span>
                    <div>
                      <h4 className="text-base font-bold text-white">{item.tabTitle}</h4>
                      <p className="text-xs text-zinc-400 mt-0.5">{item.tabSubtitle}</p>
                    </div>
                  </div>
                </button>
              )
            })}
          </div>

          {/* Right: Cryptographic Flow Display */}
          <div className="lg:col-span-7">
            <div className="neu-panel rounded-3xl p-8 border border-white/5 relative min-h-[460px] flex flex-col justify-between">
              <AnimatePresence mode="wait">
                <motion.div
                  key={activeTab}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  transition={{ duration: 0.25 }}
                >
                  <div className="flex items-center justify-between pb-4 border-b border-white/5">
                    <span className="text-xs font-mono font-bold text-neonLime px-3 py-1 rounded-full neu-inset">
                      {d.badge}
                    </span>
                    <span className="text-xs font-mono text-zinc-500">Arc Precompile: 0x1800...0004</span>
                  </div>
                  <h3 className="text-2xl font-bold text-white mt-6">{d.title}</h3>
                  <p className="text-sm text-zinc-300 mt-3 leading-relaxed">{d.desc}</p>

                  {/* State & Crypto Preview Box */}
                  <div className="mt-6 neu-inset rounded-2xl p-5 font-mono text-xs space-y-2.5 text-zinc-300 border border-white/5">
                    <div className="flex items-center justify-between text-[11px] text-zinc-500">
                      <span>PARAMETERS DISPATCHED TO CONTRACT</span>
                      <span className="text-emerald-400">VALIDATED ONCHAIN</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-zinc-500">{d.paramLabel1}</span>
                      <span className="text-neonLime break-all">{d.param1}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-zinc-500">{d.paramLabel2}</span>
                      <span className="text-white break-all">{d.param2}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-zinc-500">{d.paramLabel3}</span>
                      <span className="text-emerald-400 break-all">{d.param3}</span>
                    </div>
                  </div>

                  {/* Bullet highlights */}
                  <div className="mt-8 pt-5 border-t border-white/5 grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs text-zinc-300">
                    <div className="flex items-center gap-2">
                      <Check className="size-4 text-neonLime shrink-0" />
                      <span>{d.bullet1}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <Check className="size-4 text-neonLime shrink-0" />
                      <span>{d.bullet2}</span>
                    </div>
                  </div>
                </motion.div>
              </AnimatePresence>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
