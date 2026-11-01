import { Link } from '@/lib/router'

export function LandingNav() {
  return (
    <header className="sticky top-0 z-50 bg-[#090c12]/85 backdrop-blur-xl border-b border-white/5 transition-all">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 h-20 flex items-center justify-between gap-4">
        {/* Brand Logo */}
        <Link to="/" className="flex items-center gap-3 group">
          <div className="size-11 rounded-2xl neu-panel flex items-center justify-center text-neonLime group-hover:border-neonLime/40 transition-colors">
            <svg fill="none" height="22" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.2" viewBox="0 0 24 24" width="22" xmlns="http://www.w3.org/2000/svg">
              <line x1="3" x2="21" y1="22" y2="22"></line>
              <line x1="6" x2="6" y1="18" y2="11"></line>
              <line x1="10" x2="10" y1="18" y2="11"></line>
              <line x1="14" x2="14" y1="18" y2="11"></line>
              <line x1="18" x2="18" y1="18" y2="11"></line>
              <polygon points="12 2 20 7 4 7"></polygon>
            </svg>
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <span className="text-xl font-extrabold tracking-tight text-white leading-none">ArcStream</span>
              <span className="px-1.5 py-0.5 text-[10px] font-mono font-bold rounded-md bg-neonLime/15 text-neonLime border border-neonLime/30">PQ</span>
            </div>
            <span className="text-[11px] text-zinc-400 font-mono tracking-wide">USDC Escrow • Arc L1</span>
          </div>
        </Link>

        {/* Desktop Nav Links */}
        <nav className="hidden md:flex items-center gap-8">
          <a className="text-xs font-semibold text-zinc-300 hover:text-white tracking-wide transition-colors" href="#features">
            Features
          </a>
          <a className="text-xs font-semibold text-zinc-300 hover:text-white tracking-wide transition-colors" href="#how-it-works">
            Protocol Architecture
          </a>
          <a className="text-xs font-semibold text-zinc-300 hover:text-white tracking-wide transition-colors flex items-center gap-1.5" href="#security">
            <span>Security Audit</span>
            <span className="size-1.5 rounded-full bg-neonLime"></span>
          </a>
          <a className="text-xs font-semibold text-zinc-300 hover:text-white tracking-wide transition-colors" href="#contract">
            Smart Contract
          </a>
        </nav>

        {/* Action Area */}
        <div className="flex items-center gap-3">
          <Link
            to="/dashboard"
            className="neu-btn-primary px-5 py-2.5 rounded-xl font-bold text-xs flex items-center gap-2 tracking-wide"
          >
            <span>Launch App</span>
            <svg fill="none" height="14" stroke="currentColor" strokeWidth="2.5" viewBox="0 0 24 24" width="14" xmlns="http://www.w3.org/2000/svg">
              <path d="M5 12h14"></path>
              <path d="m12 5 7 7-7 7"></path>
            </svg>
          </Link>
        </div>
      </div>

      {/* Mobile Links Bar */}
      <nav aria-label="Primary mobile" className="flex justify-center gap-4 border-t border-white/5 px-2 py-2 md:hidden bg-[#090c12]">
        <a className="text-xs font-medium text-zinc-400 hover:text-white" href="#features">Features</a>
        <a className="text-xs font-medium text-zinc-400 hover:text-white" href="#how-it-works">Architecture</a>
        <a className="text-xs font-medium text-zinc-400 hover:text-white" href="#security">Security</a>
        <a className="text-xs font-medium text-zinc-400 hover:text-white" href="#contract">Contract</a>
      </nav>
    </header>
  )
}
