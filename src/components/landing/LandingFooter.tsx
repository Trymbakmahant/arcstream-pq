import { ExternalLink } from 'lucide-react'
import { Link } from '@/lib/router'

const LINKS = [
  { label: 'DoraHacks', href: 'https://dorahacks.io' },
  { label: 'Arc Network documentation', href: 'https://docs.arc.io' },
]

export function LandingFooter() {
  return (
    <footer className="bg-brandHighlight text-brandMain">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-4 py-8 sm:px-6">
        <p className="text-sm">Built with Arc Studio for Arc Microgrants Round 2</p>
        <nav aria-label="Footer" className="flex flex-wrap items-center gap-x-6 gap-y-1">
          <Link to="/dashboard" className="inline-flex min-h-11 items-center text-sm font-semibold hover:underline">
            Launch App
          </Link>
          {LINKS.map((link) => (
            <a
              key={link.label}
              href={link.href}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex min-h-11 items-center gap-1 text-sm text-brandMain/90 hover:text-brandMain hover:underline"
            >
              {link.label}
              <ExternalLink className="size-3" />
            </a>
          ))}
        </nav>
      </div>
    </footer>
  )
}
