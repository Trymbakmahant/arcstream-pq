import { ArrowRight, ArrowUpRight } from 'lucide-react'
import { Link } from '@/lib/router'
import { VAULT_ADDRESS } from '@/contracts/vault'
import { NETWORK } from '@/lib/network'

const PRECOMPILE = '0x1800000000000000000000000000000000000004'

export function SmartContractSection() {
  return (
    <section className="py-24 px-6 bg-[#080a0f] border-t border-white/5 relative" id="contract">
      <div className="max-w-6xl mx-auto">
        <div className="neu-panel rounded-3xl p-8 sm:p-12 border border-white/10 relative overflow-hidden">
          <div className="pointer-events-none absolute -bottom-10 -right-10 w-80 h-80 bg-neonLime/10 rounded-full blur-3xl"></div>
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
            <div className="lg:col-span-7">
              <div className="inline-flex items-center gap-2 neu-inset px-3 py-1.5 rounded-full text-xs font-mono text-zinc-300 mb-4">
                <span className="size-2 rounded-full bg-amber-400"></span>
                <span>DoraHacks Arc Microgrants Round 2 Cohort</span>
              </div>
              <h2 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight">
                Deploying Next-Gen Escrows on Arc
              </h2>
              <p className="mt-4 text-zinc-300 text-sm sm:text-base leading-relaxed">
                ArcStream-PQ is engineered to showcase native USDC gas execution and hardware post-quantum validation directly on Arc. Open for testing and production integration.
              </p>
              <div className="mt-8 flex flex-wrap gap-4">
                <Link
                  className="neu-btn-primary px-7 py-3.5 rounded-xl font-bold text-xs tracking-wide flex items-center gap-2"
                  to="/dashboard"
                >
                  <span>Enter DApp</span>
                  <ArrowRight className="size-3.5" />
                </Link>
                <a
                  className="neu-btn-secondary px-6 py-3.5 rounded-xl font-semibold text-xs text-zinc-300 flex items-center gap-2"
                  href="https://dorahacks.io"
                  rel="noopener noreferrer"
                  target="_blank"
                >
                  <span>DoraHacks BUIDL</span>
                  <ArrowUpRight className="size-3.5 text-zinc-500" />
                </a>
              </div>
            </div>
            <div className="lg:col-span-5 space-y-3">
              <div className="neu-inset p-5 rounded-2xl border border-white/5">
                <div className="flex items-center justify-between text-xs font-mono text-zinc-400 mb-1">
                  <span>MAIN CONTRACT</span>
                  <span className="text-emerald-400 font-bold uppercase">{NETWORK.label}</span>
                </div>
                <code className="text-xs font-mono text-neonLime break-all select-all block py-1 font-bold">
                  {VAULT_ADDRESS ?? '0x464504fe41fef085413c52cfc6fdbeb15637c0fd'}
                </code>
              </div>
              <div className="neu-inset p-5 rounded-2xl border border-white/5">
                <div className="flex items-center justify-between text-xs font-mono text-zinc-400 mb-1">
                  <span>SLH-DSA PRECOMPILE</span>
                  <span className="text-cyan-400 font-bold">NATIVE VERIFIER</span>
                </div>
                <code className="text-xs font-mono text-zinc-300 break-all select-all block py-1">
                  {PRECOMPILE}
                </code>
              </div>
              <div className="neu-inset p-5 rounded-2xl border border-white/5">
                <div className="flex items-center justify-between text-xs font-mono text-zinc-400 mb-1">
                  <span>GAS ASSET</span>
                  <span className="text-zinc-300 font-bold">NATIVE TOKEN</span>
                </div>
                <span className="text-xs font-mono text-white font-bold block py-1">
                  Circle USD Coin (USDC)
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

