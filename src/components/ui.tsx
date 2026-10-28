import { Check, ExternalLink } from 'lucide-react'
import type { MilestoneStatus } from '@/hooks/useEscrows'

export function StatusBadge({ status }: { status: MilestoneStatus }) {
  const base =
    'inline-flex min-h-7 items-center gap-1 rounded-full px-3 text-[0.6875rem] font-bold tracking-[0.08em]'
  switch (status) {
    case 'PENDING':
      return <span className={`${base} border border-brandSecondary text-brandHighlight`}>PENDING</span>
    case 'WORK SUBMITTED':
      return <span className={`${base} bg-brandSecondary/60 text-brandHighlight`}>WORK SUBMITTED</span>
    case 'APPROVED':
      return <span className={`${base} bg-brandHighlight text-brandMain`}>APPROVED</span>
    case 'RELEASED':
      return (
        <span className={`${base} border border-brandHighlight/25 text-brandHighlight/60`}>
          <Check className="size-3" />
          RELEASED
        </span>
      )
    case 'CLOSED':
      return (
        <span className={`${base} border border-dashed border-brandHighlight/30 text-brandHighlight/60`}>
          CLOSED
        </span>
      )
  }
}

export function ProgressBar({
  total,
  released,
  approved,
}: {
  total: bigint
  released: bigint
  approved: bigint
}) {
  const pct = (value: bigint) => (total === 0n ? 0 : Number((value * 10000n) / total) / 100)
  const releasedPct = pct(released)
  const approvedPct = Math.min(pct(approved), 100 - releasedPct)
  return (
    <div
      className="flex h-2.5 w-full overflow-hidden rounded-full bg-brandSecondary/30"
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(releasedPct)}
      aria-label="Paid out"
    >
      <div className="h-full bg-brandHighlight" style={{ width: `${releasedPct}%` }} />
      <div className="h-full bg-brandSecondary" style={{ width: `${approvedPct}%` }} />
    </div>
  )
}

const HTTP_PROOF = /^https?:\/\/\S+$/i
const IPFS_PROOF = /^ipfs:\/\/(\S+)$/i
const BARE_CID = /^(Qm[1-9A-HJ-NP-Za-km-z]{44}|b[a-z2-7]{58,})$/

/** Turn a proof string into a safe http(s) link when it looks like a URL or IPFS CID. */
export function proofHref(proof: string): string | null {
  const value = proof.trim()
  if (HTTP_PROOF.test(value)) return value
  const ipfs = IPFS_PROOF.exec(value)
  if (ipfs) return `https://ipfs.io/ipfs/${ipfs[1]}`
  if (BARE_CID.test(value)) return `https://ipfs.io/ipfs/${value}`
  return null
}

export function ProofLink({ proof }: { proof: string }) {
  const href = proofHref(proof)
  if (!href) {
    return (
      <span className="break-all font-mono text-xs text-brandHighlight" title="Work proof">
        {proof}
      </span>
    )
  }
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex min-h-8 max-w-full items-center gap-1 break-all font-mono text-xs font-medium text-brandHighlight underline underline-offset-2"
    >
      {proof.length > 48 ? `${proof.slice(0, 44)}...` : proof}
      <ExternalLink className="size-3 shrink-0" />
    </a>
  )
}
