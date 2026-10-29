import { ArrowRight, Landmark } from 'lucide-react'
import { Link } from '@/lib/router'
import { addressUrl, VAULT_ADDRESS } from '@/contracts/vault'
import { NETWORK } from '@/lib/network'

const explorerHref = VAULT_ADDRESS ? addressUrl(VAULT_ADDRESS) : NETWORK.explorerUrl

const LINKS = [
  { label: 'How It Works', href: '#how-it-works', external: false },
  { label: 'Post-Quantum Security', href: '#security', external: false },
  { label: 'Explorer', href: explorerHref, external: true },
]

export function LandingNav() {
  return (
    <header className="sticky top-0 z-40 border-b border-brandHighlight/10 bg-brandMain/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
        <Link to="/" className="flex items-center gap-3">
          <span className="flex size-10 items-center justify-center rounded-xl bg-brandHighlight text-brandMain">
            <Landmark className="size-5" />
          </span>
          <span>
            <span className="display block text-lg font-bold leading-none text-brandHighlight">ArcStream-PQ</span>
            <span className="mt-1 hidden text-xs text-brandHighlight/70 sm:block">USDC Milestone Protocol on Arc</span>
          </span>
        </Link>

        <nav aria-label="Primary" className="hidden items-center gap-1 md:flex">
          {LINKS.map((link) => (
            <a
              key={link.label}
              href={link.href}
              {...(link.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
              className="inline-flex min-h-11 items-center rounded-xl px-4 text-sm font-medium text-brandHighlight/80 transition-colors hover:bg-brandSecondary/30 hover:text-brandHighlight"
            >
              {link.label}
            </a>
          ))}
        </nav>

        <Link
          to="/dashboard"
          className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-brandHighlight px-5 py-2.5 text-sm font-semibold text-brandMain transition-opacity hover:opacity-90"
        >
          Launch App
          <ArrowRight className="size-4" />
        </Link>
      </div>

      <nav aria-label="Primary mobile" className="flex justify-center gap-1 border-t border-brandHighlight/10 px-2 py-1 md:hidden">
        {LINKS.map((link) => (
          <a
            key={link.label}
            href={link.href}
            {...(link.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
            className="inline-flex min-h-11 items-center rounded-lg px-3 text-xs font-medium text-brandHighlight/80 hover:text-brandHighlight"
          >
            {link.label}
          </a>
        ))}
      </nav>
    </header>
  )
}
