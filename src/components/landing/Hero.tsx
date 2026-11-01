import { ArrowRight, ChevronDown, Coins, ExternalLink, Fingerprint, Lock, ShieldCheck } from 'lucide-react'
import { motion } from 'framer-motion'
import { VAULT_ADDRESS, addressUrl } from '@/contracts/vault'
import { Link } from '@/lib/router'
import { NETWORK } from '@/lib/network'
import { SoftAuroraBackground } from '@/components/landing/SoftAuroraBackground'

const explorerHref = VAULT_ADDRESS ? addressUrl(VAULT_ADDRESS) : NETWORK.explorerUrl

export function Hero() {
  return (
    <>
      {/* HERO SECTION */}
      <section className="relative pt-20 pb-24 px-6 overflow-hidden">
        {/* Soft Aurora WebGL Motion Background */}
        <SoftAuroraBackground />

        <div className="max-w-6xl mx-auto text-center relative z-10">
          {/* FIPS 205 Badge */}
          <motion.div
            className="inline-flex items-center gap-2.5 neu-inset px-4 py-1.5 rounded-full text-xs font-mono text-zinc-300 border border-white/10 mb-8"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4 }}
          >
            <span className="size-2 rounded-full bg-neonLime shadow-glow-lime animate-ping"></span>
            <span className="text-neonLime font-bold uppercase tracking-wider">NIST FIPS 205</span>
            <span className="text-zinc-500">•</span>
            <span>Post-Quantum SLH-DSA Milestone Escrow</span>
          </motion.div>

          {/* Main Headline */}
          <motion.h1
            className="text-4xl sm:text-6xl lg:text-7xl font-extrabold tracking-tight text-white leading-[1.08] max-w-4xl mx-auto"
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
          >
            Pay for finished work, <br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-neonLime via-white to-neonPink">
              milestone by milestone.
            </span>
          </motion.h1>

          {/* Subtitle */}
          <motion.p
            className="mt-7 text-base sm:text-lg text-zinc-300 font-normal leading-relaxed max-w-2xl mx-auto"
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.2 }}
          >
            Institutional noncustodial USDC escrow on Arc. Secured with quantum-resistant stateless hash signatures and
            authenticated by biometric hardware on every release.
          </motion.p>

          {/* Primary CTA buttons */}
          <motion.div
            className="mt-10 flex flex-wrap items-center justify-center gap-4"
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.3 }}
          >
            <Link
              to="/dashboard"
              className="neu-btn-primary px-8 py-4 rounded-2xl font-extrabold text-sm flex items-center gap-3"
            >
              <span>Launch ArcStream Protocol</span>
              <ArrowRight className="size-4" />
            </Link>
            <a
              className="neu-btn-secondary px-6 py-4 rounded-2xl font-semibold text-sm text-zinc-200 flex items-center gap-2"
              href={explorerHref}
              rel="noopener noreferrer"
              target="_blank"
            >
              <span>View Contract on Explorer</span>
              <ExternalLink className="size-4" />
            </a>
            <a
              className="neu-btn-secondary px-5 py-4 rounded-2xl font-mono text-xs text-zinc-400 hover:text-neonLime flex items-center gap-2"
              href="#how-it-works"
            >
              <span>Protocol Spec</span>
              <ChevronDown className="size-4" />
            </a>
          </motion.div>

          {/* Live Protocol Metric Bar / Ticker */}
          <motion.div
            className="mt-16 neu-panel rounded-3xl p-6 sm:p-8 max-w-5xl mx-auto border border-white/5"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.4 }}
          >
            <div className="grid grid-cols-2 md:grid-cols-4 gap-6 text-left">
              <div className="neu-inset p-4 rounded-2xl">
                <span className="block text-[11px] font-mono uppercase tracking-wider text-zinc-400">Total Escrow Value</span>
                <div className="text-2xl font-extrabold text-white mt-1 flex items-baseline gap-1.5 font-mono">
                  $148,250 <span className="text-xs font-semibold text-neonLime">USDC</span>
                </div>
                <div className="mt-1 flex items-center gap-1.5 text-[11px] text-zinc-400">
                  <span className="size-1.5 rounded-full bg-neonLime"></span>
                  <span>100% Native on Arc</span>
                </div>
              </div>

              <div className="neu-inset p-4 rounded-2xl">
                <span className="block text-[11px] font-mono uppercase tracking-wider text-zinc-400">Ghosting Incident Rate</span>
                <div className="text-2xl font-extrabold text-white mt-1 flex items-baseline gap-1.5 font-mono">
                  0.00%
                </div>
                <div className="mt-1 flex items-center gap-1.5 text-[11px] text-neonPink">
                  <span className="size-1.5 rounded-full bg-neonPink"></span>
                  <span>Artifact Lock Enforced</span>
                </div>
              </div>

              <div className="neu-inset p-4 rounded-2xl">
                <span className="block text-[11px] font-mono uppercase tracking-wider text-zinc-400">Quantum Verification</span>
                <div className="text-2xl font-extrabold text-white mt-1 flex items-baseline gap-1.5 font-mono">
                  &lt; 140ms
                </div>
                <div className="mt-1 flex items-center gap-1.5 text-[11px] text-zinc-400">
                  <span className="size-1.5 rounded-full bg-neonLime"></span>
                  <span>Precompile 0x18...4</span>
                </div>
              </div>

              <div className="neu-inset p-4 rounded-2xl">
                <span className="block text-[11px] font-mono uppercase tracking-wider text-zinc-400">Supported Currencies</span>
                <div className="text-2xl font-extrabold text-white mt-1 flex items-baseline gap-1.5 font-mono">
                  Native USDC
                </div>
                <div className="mt-1 flex items-center gap-1.5 text-[11px] text-zinc-400">
                  <span className="size-1.5 rounded-full bg-cyan-400"></span>
                  <span>Zero-Slippage Gas</span>
                </div>
              </div>
            </div>
          </motion.div>
        </div>
      </section>

      {/* PROTOCOL PILLARS / FEATURES SECTION */}
      <section className="py-24 px-6 border-t border-white/5 relative" id="features">
        <div className="max-w-6xl mx-auto">
          <div className="text-center max-w-3xl mx-auto">
            <p className="font-mono text-xs uppercase tracking-widest text-neonLime font-bold">Core Architecture</p>
            <h2 className="text-3xl sm:text-4xl font-extrabold text-white mt-2">
              Engineered for High-Stakes Milestone Settlement
            </h2>
            <p className="text-zinc-400 text-sm sm:text-base mt-3">
              Combining post-quantum cryptography with deterministic state machines to eliminate client ghosting and key
              theft vulnerability.
            </p>
          </div>

          <div className="mt-16 grid grid-cols-1 md:grid-cols-3 gap-8">
            {/* Pillar 1 */}
            <div className="neu-panel neu-panel-hover rounded-3xl p-7 flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between mb-6">
                  <div className="size-14 rounded-2xl neu-inset flex items-center justify-center text-neonLime">
                    <Coins className="size-6" />
                  </div>
                  <span className="font-mono text-xs px-3 py-1 rounded-full neu-inset text-neonLime font-bold">
                    01 • Gas-Native
                  </span>
                </div>
                <h3 className="text-xl font-bold text-white mb-2">USDC-Native Gas on Arc</h3>
                <p className="text-sm text-zinc-400 leading-relaxed">
                  Every deposit, milestone release, and dispute check pays transaction gas straight in native Circle USDC
                  on Arc. Eliminates cross-chain swap friction, secondary token volatility, and leftover dust.
                </p>
              </div>
              <div className="mt-6 pt-4 border-t border-white/5 flex items-center justify-between text-xs font-mono text-zinc-400">
                <span>Direct ERC-20 debit</span>
                <span className="text-neonLime font-semibold">Zero Slippage</span>
              </div>
            </div>

            {/* Pillar 2 */}
            <div className="neu-panel neu-panel-hover rounded-3xl p-7 flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between mb-6">
                  <div className="size-14 rounded-2xl neu-inset flex items-center justify-center text-neonPink">
                    <Lock className="size-6" />
                  </div>
                  <span className="font-mono text-xs px-3 py-1 rounded-full neu-inset text-neonPink font-bold">
                    02 • Safeguard
                  </span>
                </div>
                <h3 className="text-xl font-bold text-white mb-2">Anti-Ghosting Deliverable Lock</h3>
                <p className="text-sm text-zinc-400 leading-relaxed">
                  Contractor deliverable submission immediately freezes unilateral client cancellation. If a client attempts
                  to go dark, the smart contract automatically initiates an uncontested payout settlement countdown.
                </p>
              </div>
              <div className="mt-6 pt-4 border-t border-white/5 flex items-center justify-between text-xs font-mono text-zinc-400">
                <span>IPFS / Hash anchored</span>
                <span className="text-neonPink font-semibold">Auto-Settlement</span>
              </div>
            </div>

            {/* Pillar 3 */}
            <div className="neu-panel neu-panel-hover rounded-3xl p-7 flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between mb-6">
                  <div className="size-14 rounded-2xl neu-inset flex items-center justify-center text-cyan-400">
                    <Fingerprint className="size-6" />
                  </div>
                  <span className="font-mono text-xs px-3 py-1 rounded-full neu-inset text-cyan-400 font-bold">
                    03 • Quantum 2FA
                  </span>
                </div>
                <h3 className="text-xl font-bold text-white mb-2">Hardware Touch ID &amp; FIPS 205</h3>
                <p className="text-sm text-zinc-400 leading-relaxed">
                  Every milestone unlock triggers an isolated Web Worker generating NIST FIPS 205 SLH-DSA signatures verified
                  via Arc’s native precompile contract, immune to Shor's algorithm and compromised seed phrases.
                </p>
              </div>
              <div className="mt-6 pt-4 border-t border-white/5 flex items-center justify-between text-xs font-mono text-zinc-400">
                <span>Precompile verified</span>
                <span className="text-cyan-400 font-semibold">Passkey Biometric</span>
              </div>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
