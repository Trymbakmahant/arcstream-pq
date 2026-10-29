import { useState } from 'react'
import { toast } from 'sonner'
import { Check, Copy, ExternalLink } from 'lucide-react'
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

export type ProofKind = 'url' | 'ipfs' | 'text'

export interface ProofInfo {
  kind: ProofKind
  /** Safe http(s) link for url and ipfs proofs. */
  href?: string
  /** Short readable label such as "figma.com/file/abc..." or "ipfs://Qm...". */
  label: string
}

const BARE_CID = /^(Qm[1-9A-HJ-NP-Za-km-z]{44}|b[a-z2-7]{58,})(\/\S*)?$/
const IPFS_URI = /^ipfs:\/\/(?:ipfs\/)?(\S+)$/i

const clip = (value: string, max: number) => (value.length > max ? `${value.slice(0, max - 1)}\u2026` : value)

/** Work out what a proof string is. Only http(s) links are ever made clickable. */
export function classifyProof(proof: string): ProofInfo {
  const value = proof.trim()

  const ipfs = IPFS_URI.exec(value)
  if (ipfs) return { kind: 'ipfs', href: `https://ipfs.io/ipfs/${ipfs[1]}`, label: `ipfs://${clip(ipfs[1], 40)}` }
  if (BARE_CID.test(value)) return { kind: 'ipfs', href: `https://ipfs.io/ipfs/${value}`, label: `ipfs://${clip(value, 40)}` }

  if (/^https?:\/\//i.test(value) && !/\s/.test(value)) {
    try {
      const url = new URL(value)
      if (url.protocol === 'http:' || url.protocol === 'https:') {
        const path = `${url.pathname}${url.search}`.replace(/\/$/, '')
        return { kind: 'url', href: url.toString(), label: clip(`${url.hostname.replace(/^www\./, '')}${path}`, 52) }
      }
    } catch {
      // Not a valid URL: fall through and show it as plain text.
    }
  }
  return { kind: 'text', label: value }
}

/** Kept for the code that only needs a link or nothing. */
export function proofHref(proof: string): string | null {
  return classifyProof(proof).href ?? null
}

export function CopyButton({ value, label = 'Copy', className = '' }: { value: string; label?: string; className?: string }) {
  const [copied, setCopied] = useState(false)
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value)
      setCopied(true)
      toast.success('Copied to clipboard')
      window.setTimeout(() => setCopied(false), 1500)
    } catch {
      toast.error('Could not copy. Select the text and copy it manually.')
    }
  }
  return (
    <button
      type="button"
      onClick={() => {
        void copy()
      }}
      className={`inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg border border-brandHighlight/15 bg-white px-2.5 text-xs font-semibold text-brandHighlight transition-colors hover:bg-brandSecondary/30 ${className}`}
      aria-label={`${label}${copied ? ' (copied)' : ''}`}
    >
      {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
      {copied ? 'Copied' : label}
    </button>
  )
}

/** Shows a deliverable proof: a link for URLs, a gateway link for IPFS, or copyable text for hashes. */
export function ProofViewer({ proof, compact = false }: { proof: string; compact?: boolean }) {
  const info = classifyProof(proof)
  if (info.kind === 'text') {
    return (
      <div className="flex items-start gap-2 rounded-lg border border-brandHighlight/10 bg-white p-2">
        <code className="min-w-0 flex-1 break-all px-1 py-1 font-mono text-xs text-brandHighlight" title="Work proof">
          {proof}
        </code>
        <CopyButton value={proof} />
      </div>
    )
  }
  return (
    <div className="flex flex-wrap items-center gap-2">
      <a
        href={info.href}
        target="_blank"
        rel="noopener noreferrer"
        className={`inline-flex min-w-0 max-w-full items-center gap-2 rounded-lg border border-brandHighlight/15 bg-white font-semibold text-brandHighlight transition-colors hover:bg-brandSecondary/30 ${
          compact ? 'min-h-9 px-2.5 text-xs' : 'min-h-11 px-3.5 text-sm'
        }`}
      >
        <ExternalLink className="size-4 shrink-0" />
        <span className="min-w-0 break-all">
          {info.kind === 'ipfs' ? 'Open on IPFS' : 'Open Deliverable'}{' '}
          <span className="font-mono text-[0.6875rem] font-normal text-brandHighlight/70">({info.label})</span>
        </span>
      </a>
      <CopyButton value={proof.trim()} label="Copy link" />
    </div>
  )
}

/** Existing name used across the app. */
export const ProofLink = ProofViewer
