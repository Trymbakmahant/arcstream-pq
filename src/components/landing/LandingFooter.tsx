import { ArrowUp } from 'lucide-react'
import { Link } from '@/lib/router'
import { VAULT_ADDRESS, addressUrl } from '@/contracts/vault'
import { NETWORK } from '@/lib/network'

const explorerHref = VAULT_ADDRESS ? addressUrl(VAULT_ADDRESS) : NETWORK.explorerUrl

export function LandingFooter() {
  const scrollToTop = () => {
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  return (
    <footer className="pt-16 pb-12 px-6 border-t border-white/5 bg-[#06080d]">
      <div className="max-w-6xl mx-auto">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-10 pb-12 border-b border-white/5">
          {/* Col 1: Brand */}
          <div className="md:col-span-2 space-y-4">
            <div className="flex items-center gap-3">
              <div className="size-10 rounded-xl neu-panel flex items-center justify-center text-neonLime">
                <svg fill="none" height="20" stroke="currentColor" strokeWidth="2.2" viewBox="0 0 24 24" width="20" xmlns="http://www.w3.org/2000/svg">
                  <line x1="3" x2="21" y1="22" y2="22"></line>
                  <line x1="6" x2="6" y1="18" y2="11"></line>
                  <line x1="10" x2="10" y1="18" y2="11"></line>
                  <line x1="14" x2="14" y1="18" y2="11"></line>
                  <line x1="18" x2="18" y1="18" y2="11"></line>
                  <polygon points="12 2 20 7 4 7"></polygon>
                </svg>
              </div>
              <span className="text-lg font-extrabold text-white">
                ArcStream<span className="text-neonLime font-mono text-sm ml-1">-PQ</span>
              </span>
            </div>
            <p className="text-xs text-zinc-400 leading-relaxed max-w-sm">
              Institutional post-quantum milestone protocol. Pay for verified deliverables with zero gas swap slippage on Arc.
            </p>
            <div className="flex items-center gap-2 text-xs font-mono text-zinc-500">
              <span className="size-2 rounded-full bg-emerald-400"></span>
              <span>{NETWORK.label} Live</span>
            </div>
          </div>

          {/* Col 2: Protocol */}
          <div>
            <h5 className="text-xs font-mono uppercase tracking-wider text-white font-bold mb-4">Protocol</h5>
            <ul className="space-y-2.5 text-xs text-zinc-400">
              <li><a className="hover:text-neonLime transition-colors" href="#features">Features</a></li>
              <li><a className="hover:text-neonLime transition-colors" href="#how-it-works">Architecture</a></li>
              <li><a className="hover:text-neonLime transition-colors" href="#security">Security Matrix</a></li>
              <li><Link className="hover:text-neonLime transition-colors" to="/dashboard">Launch DApp</Link></li>
            </ul>
          </div>

          {/* Col 3: Developers */}
          <div>
            <h5 className="text-xs font-mono uppercase tracking-wider text-white font-bold mb-4">Developers</h5>
            <ul className="space-y-2.5 text-xs text-zinc-400">
              <li>
                <a className="hover:text-white transition-colors" href="https://docs.arc.io" rel="noopener noreferrer" target="_blank">
                  Arc Network Docs
                </a>
              </li>
              <li>
                <a className="hover:text-white transition-colors" href={explorerHref} rel="noopener noreferrer" target="_blank">
                  Block Explorer
                </a>
              </li>
              <li>
                <a className="hover:text-white transition-colors" href="https://csrc.nist.gov/pubs/fips/205/final" rel="noopener noreferrer" target="_blank">
                  NIST FIPS 205 Spec
                </a>
              </li>
              <li>
                <a className="hover:text-white transition-colors" href="https://github.com" rel="noopener noreferrer" target="_blank">
                  GitHub Repository
                </a>
              </li>
            </ul>
          </div>

          {/* Col 4: Ecosystem */}
          <div>
            <h5 className="text-xs font-mono uppercase tracking-wider text-white font-bold mb-4">Ecosystem</h5>
            <ul className="space-y-2.5 text-xs text-zinc-400">
              <li>
                <a className="hover:text-white transition-colors" href="https://dorahacks.io" rel="noopener noreferrer" target="_blank">
                  DoraHacks Grants
                </a>
              </li>
              <li>
                <a className="hover:text-white transition-colors" href="https://circle.com/usdc" rel="noopener noreferrer" target="_blank">
                  Circle USDC
                </a>
              </li>
              <li>
                <a className="hover:text-white transition-colors" href="https://arc.io" rel="noopener noreferrer" target="_blank">
                  Arc L1 Network
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom Credits */}
        <div className="pt-8 flex flex-col sm:flex-row items-center justify-between text-xs font-mono text-zinc-500 gap-4">
          <div>
            © 2025 ArcStream-PQ Protocol. Built for DoraHacks Arc Microgrants Round 2.
          </div>
          <div className="flex items-center gap-6">
            <a className="hover:text-zinc-300" href="#features">Privacy &amp; Terms</a>
            <button
              type="button"
              onClick={scrollToTop}
              className="hover:text-neonLime flex items-center gap-1 cursor-pointer"
            >
              <span>Back to Top</span>
              <ArrowUp className="size-3" />
            </button>
          </div>
        </div>
      </div>
    </footer>
  )
}
