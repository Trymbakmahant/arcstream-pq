import { useRef, useState } from 'react'
import { AnimatePresence, motion, useMotionValueEvent, useScroll } from 'framer-motion'
import { ArrowDown, Check, ShieldCheck, Terminal } from 'lucide-react'

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
  const containerRef = useRef<HTMLDivElement>(null)
  const [activeTab, setActiveTab] = useState(0)
  const [scrollProgress, setScrollProgress] = useState(0)
  const isManualRef = useRef(false)
  const timeoutRef = useRef<NodeJS.Timeout | null>(null)

  // Track scroll position through the tall container
  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ['start start', 'end end'],
  })

  useMotionValueEvent(scrollYProgress, 'change', (latest) => {
    setScrollProgress(latest)
    if (isManualRef.current) return

    // Switch phases based on scroll depth:
    // 0% - 35%: Stage 1 (Deposit)
    // 35% - 70%: Stage 2 (Deliverable Lock)
    // 70% - 100%: Stage 3 (Biometric PQ Release)
    if (latest < 0.35) {
      setActiveTab(0)
    } else if (latest < 0.70) {
      setActiveTab(1)
    } else {
      setActiveTab(2)
    }
  })

  const handleTabClick = (index: number) => {
    setActiveTab(index)
    isManualRef.current = true
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    timeoutRef.current = setTimeout(() => {
      isManualRef.current = false
    }, 850)

    if (containerRef.current) {
      const rect = containerRef.current.getBoundingClientRect()
      const scrollTop = window.scrollY || document.documentElement.scrollTop
      const containerTop = rect.top + scrollTop
      const scrollableDist = containerRef.current.offsetHeight - window.innerHeight
      const targetPercent = index === 0 ? 0.08 : index === 1 ? 0.50 : 0.88
      const targetY = containerTop + scrollableDist * targetPercent
      window.scrollTo({ top: targetY, behavior: 'smooth' })
    }
  }

  const d = STEP_DATA[activeTab]

  return (
    <div
      ref={containerRef}
      className="relative min-h-[260vh] bg-[#080b10] border-t border-white/5"
      id="how-it-works"
    >
      {/* Sticky Viewport Container: stays pinned at top when reached */}
      <div className="sticky top-20 z-20 flex min-h-[calc(100vh-5rem)] flex-col justify-center px-4 py-8 sm:px-6">
        <div className="max-w-6xl mx-auto w-full">
          {/* Header */}
          <motion.div
            className="text-center max-w-3xl mx-auto mb-10 sm:mb-12"
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: '-40px' }}
            transition={{ duration: 0.5 }}
          >
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full neu-inset text-xs font-mono font-semibold text-neonLime mb-3">
              <span className="size-2 rounded-full bg-neonLime shadow-[0_0_8px_#d4ff3f]" />
              <span>Scroll-Driven Lifecycle Walkthrough</span>
            </div>
            <h2 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight">
              Zero-Trust Escrow from Deposit to Release
            </h2>
            <p className="text-zinc-400 text-sm sm:text-base mt-2">
              Scroll down to step through cryptographic state transitions executed on Arc.
            </p>

            {/* Scroll Progress Bar & Phase Pill */}
            <div className="mt-4 flex flex-col sm:flex-row items-center justify-center gap-3">
              <div className="h-1.5 w-48 sm:w-64 rounded-full neu-inset overflow-hidden">
                <motion.div
                  className="h-full bg-neonLime shadow-glow-lime rounded-full"
                  style={{ width: `${Math.min(100, Math.max(8, scrollProgress * 100))}%` }}
                />
              </div>
              <span className="font-mono text-xs text-zinc-400">
                Phase <strong className="text-neonLime">0{activeTab + 1}</strong> of 03
                {activeTab < 2 ? (
                  <span className="inline-flex items-center gap-1 ml-2 text-[11px] text-zinc-500">
                    (Scroll down <ArrowDown className="size-3 text-neonLime animate-bounce" />)
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 ml-2 text-[11px] text-neonLime font-semibold">
                    (Final Stage Reached)
                  </span>
                )}
              </span>
            </div>
          </motion.div>

          {/* 3-Step Interactive Grid */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-stretch">
            {/* Left: Step Selection Tabs */}
            <div className="lg:col-span-5 space-y-4 flex flex-col justify-between" role="tablist" aria-label="Lifecycle walkthrough stages">
              {STEP_DATA.map((item, index) => {
                const selected = index === activeTab
                return (
                  <button
                    key={item.stepNum}
                    type="button"
                    role="tab"
                    aria-selected={selected}
                    onClick={() => handleTabClick(index)}
                    className={`w-full text-left p-5 rounded-2xl transition-all border group relative overflow-hidden ${
                      selected
                        ? 'tab-active'
                        : 'neu-panel border-white/5 hover:border-white/10'
                    }`}
                  >
                    {selected && (
                      <motion.div
                        layoutId="activeTabIndicator"
                        className="absolute left-0 top-0 bottom-0 w-1 bg-neonLime shadow-glow-lime"
                        transition={{ type: 'spring', stiffness: 350, damping: 30 }}
                      />
                    )}
                    <div className="flex items-center gap-3.5">
                      <span
                        className={`size-9 rounded-xl neu-inset font-mono text-xs font-bold flex items-center justify-center transition-colors shrink-0 ${
                          selected
                            ? 'text-neonLime border border-neonLime/30 shadow-glow-lime'
                            : 'text-zinc-500 group-hover:text-neonLime'
                        }`}
                      >
                        0{item.stepNum}
                      </span>
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <h4 className="text-base font-bold text-white truncate">{item.tabTitle}</h4>
                          {selected && (
                            <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-neonLime px-1.5 py-0.5 rounded bg-neonLime/10 border border-neonLime/30">
                              Active
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-zinc-400 mt-0.5 line-clamp-1">{item.tabSubtitle}</p>
                      </div>
                    </div>
                  </button>
                )
              })}

              <div className="hidden lg:flex items-center justify-between neu-inset rounded-xl p-3 text-xs font-mono text-zinc-400">
                <span className="flex items-center gap-2">
                  <Terminal className="size-3.5 text-neonLime" />
                  <span>Arc Precompile: 0x18...0004</span>
                </span>
                <span className="text-emerald-400 font-semibold">FIPS 205 VERIFIED</span>
              </div>
            </div>

            {/* Right: Cryptographic Flow Display */}
            <div className="lg:col-span-7">
              <div className="neu-panel rounded-3xl p-6 sm:p-8 border border-white/5 relative min-h-[440px] flex flex-col justify-between overflow-hidden shadow-2xl">
                {/* Ambient glow behind right panel */}
                <div className="pointer-events-none absolute -bottom-16 -right-16 size-64 bg-neonLime/10 rounded-full blur-3xl" />

                <AnimatePresence mode="wait">
                  <motion.div
                    key={activeTab}
                    initial={{ opacity: 0, y: 14, scale: 0.99 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: -14, scale: 0.99 }}
                    transition={{ duration: 0.28, ease: 'easeOut' }}
                    className="flex-1 flex flex-col justify-between"
                  >
                    <div>
                      <div className="flex flex-wrap items-center justify-between gap-2 pb-4 border-b border-white/5">
                        <span className="text-xs font-mono font-bold text-neonLime px-3 py-1 rounded-full neu-inset border border-neonLime/20">
                          {d.badge}
                        </span>
                        <span className="text-xs font-mono text-zinc-400 flex items-center gap-1.5">
                          <ShieldCheck className="size-3.5 text-emerald-400" />
                          <span>Onchain Execution</span>
                        </span>
                      </div>

                      <h3 className="text-2xl font-bold text-white mt-6 tracking-tight">{d.title}</h3>
                      <p className="text-sm text-zinc-300 mt-3 leading-relaxed">{d.desc}</p>

                      {/* State & Crypto Preview Box */}
                      <div className="mt-6 neu-inset rounded-2xl p-5 font-mono text-xs space-y-2.5 text-zinc-300 border border-white/5">
                        <div className="flex items-center justify-between text-[11px] text-zinc-500 pb-1 border-b border-white/5">
                          <span>PARAMETERS DISPATCHED TO CONTRACT</span>
                          <span className="text-emerald-400 font-bold">VALIDATED ONCHAIN</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-zinc-500">{d.paramLabel1}</span>
                          <span className="text-neonLime font-semibold break-all">{d.param1}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-zinc-500">{d.paramLabel2}</span>
                          <span className="text-white font-medium break-all">{d.param2}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-zinc-500">{d.paramLabel3}</span>
                          <span className="text-emerald-400 font-semibold break-all">{d.param3}</span>
                        </div>
                      </div>
                    </div>

                    {/* Bullet highlights */}
                    <div className="mt-6 pt-5 border-t border-white/5 grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs text-zinc-300">
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
      </div>
    </div>
  )
}
