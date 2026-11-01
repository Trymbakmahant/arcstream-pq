import { useState } from 'react'
import { ExternalLink, Fingerprint, Loader2, Receipt } from 'lucide-react'
import { addressUrl } from '@/contracts/vault'
import type { EscrowView, MilestoneStatus } from '@/hooks/useEscrows'
import { useVaultActions } from '@/hooks/useVaultActions'
import { fmtUsdc, shortAddress } from '@/lib/money'
import type { MilestoneRow, RowRole } from '@/lib/rows'
import { milestoneTitle } from '@/lib/text'
import type { PqAuthRequest } from '@/components/PqAuthModal'
import { useInvoice } from '@/components/dashboard/invoiceContext'
import { useNow } from '@/hooks/useNow'
import { claimableAt, formatDuration } from '@/lib/inspection'

interface Props {
  rows: MilestoneRow[]
  onSubmitWork: (escrow: EscrowView, index: number) => void
  onViewDetails: (role: RowRole) => (escrow: EscrowView, index: number) => void
  onPqAuth: (request: PqAuthRequest) => void
}

const STATUS_COPY: Record<MilestoneStatus, { employer: string; contractor: string; className: string }> = {
  RELEASED: {
    employer: 'Payment Released',
    contractor: 'Payment Received',
    className: 'neu-sunken border border-white/5 text-zinc-400',
  },
  APPROVED: {
    employer: 'Approved - Release',
    contractor: 'Approved - Claim',
    className: 'neu-card border border-neonLime/50 text-neonLime shadow-glow-lime font-bold',
  },
  'WORK SUBMITTED': {
    employer: 'Work Submitted - Review',
    contractor: 'Awaiting Approval',
    className: 'neu-card border border-neonPink/50 text-neonPink shadow-glow-pink font-bold',
  },
  PENDING: {
    employer: 'Pending Work',
    contractor: 'Work Due',
    className: 'neu-sunken border border-amber-500/20 text-amber-400 bg-amber-400/5',
  },
  CLOSED: {
    employer: 'Closed',
    contractor: 'Closed',
    className: 'neu-sunken border border-dashed border-white/10 text-zinc-600',
  },
}

const btnPrimary = 'btn-primary text-xs py-2 px-3.5 min-h-10'
const btnGhost = 'btn-ghost text-xs py-2 px-3.5 min-h-10'

export function EscrowTable({ rows, onSubmitWork, onViewDetails, onPqAuth }: Props) {
  const actions = useVaultActions()
  const [busy, setBusy] = useState<string | null>(null)
  const now = useNow()
  const { openInvoice } = useInvoice()

  const run = async (key: string, fn: () => Promise<boolean>) => {
    setBusy(key)
    try {
      await fn()
    } finally {
      setBusy(null)
    }
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[56rem] border-collapse text-left">
        <thead className="label-caps text-zinc-500 border-b border-white/5 bg-[#0a0d14]/60">
          <tr className="label-caps text-zinc-500 border-b border-white/5">
            <th scope="col" className="px-6 py-4 font-semibold">Counterparty / Recipient</th>
            <th scope="col" className="px-4 py-4 font-semibold">Milestone</th>
            <th scope="col" className="px-4 py-4 font-semibold">Payment Amount</th>
            <th scope="col" className="px-4 py-4 font-semibold">Milestone Scope</th>
            <th scope="col" className="px-4 py-4 font-semibold">Status</th>
            <th scope="col" className="px-6 py-4 text-right font-semibold">Action</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-white/5">
          {rows.map((row) => {
            const { escrow, index, role, milestone, status } = row
            const key = row.key
            const copy = STATUS_COPY[status]
            const working = busy === key
            return (
              <tr
                key={key}
                className={`border-t border-white/5 align-middle transition-colors hover:bg-white/[0.02] ${row.needsAction ? 'bg-neonLime/[0.04]' : ''}`}
              >
                <td className="px-6 py-4">
                  <div className="flex items-center gap-3">
                    <span
                      className={`flex size-10 shrink-0 items-center justify-center rounded-xl text-xs font-bold font-mono ${
                        role === 'employer'
                          ? 'bg-neonLime/20 border border-neonLime/30 text-neonLime'
                          : 'bg-neonPink/20 border border-neonPink/30 text-neonPink'
                      }`}
                    >
                      {row.counterparty.slice(2, 4).toUpperCase()}
                    </span>
                    <div className="min-w-0">
                      <a
                        href={addressUrl(row.counterparty)}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 font-mono text-sm font-semibold text-white hover:text-neonLime transition-colors"
                      >
                        {shortAddress(row.counterparty)}
                        <ExternalLink className="size-3 text-zinc-500" />
                      </a>
                      <p className="flex flex-wrap items-center gap-1.5 font-mono text-[0.6875rem] text-zinc-400">
                        ESC-{escrow.id.toString()}-M{index + 1}
                        <span className="neu-sunken rounded border border-white/5 px-1.5 py-0.5 font-sans font-semibold text-zinc-300">
                          {role === 'employer' ? 'You fund' : 'You work'}
                        </span>
                        {escrow.isPQProtected && (
                          <span
                            className="inline-flex items-center gap-0.5 rounded bg-neonPink/20 border border-neonPink/40 px-1.5 py-0.5 font-sans font-bold text-neonPink shadow-glow-pink"
                            title="Employer release and refund need Touch ID / Face ID"
                          >
                            <Fingerprint className="size-3" />
                            PQ
                          </span>
                        )}
                      </p>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-4 text-sm tabular-nums text-white">
                  <span className="font-semibold">{index + 1}</span>
                  <span className="text-zinc-500"> of {escrow.milestoneCount}</span>
                </td>
                <td className="px-4 py-4">
                  <p className="font-mono text-base font-semibold tabular-nums text-white">
                    ${fmtUsdc(milestone.amount)}
                  </p>
                  <p className="font-mono text-[0.6875rem] text-zinc-500">USDC</p>
                </td>
                <td className="max-w-56 px-4 py-4">
                  <span className="neu-sunken inline-block max-w-full rounded-lg border border-white/5 bg-[#0b0b0b] px-3 py-2 text-sm text-zinc-300">
                    <span className="line-clamp-2">{milestoneTitle(milestone.description)}</span>
                  </span>
                </td>
                <td className="px-4 py-4">
                  <span
                    className={`inline-flex min-h-8 items-center rounded-full px-3.5 py-1 text-xs font-semibold ${copy.className}`}
                  >
                    {copy[role]}
                  </span>
                </td>
                <td className="px-6 py-4">
                  <div className="flex flex-wrap items-center justify-end gap-2">
                    {role === 'employer' && status === 'WORK SUBMITTED' && (
                      <button
                        type="button"
                        className={btnPrimary}
                        disabled={busy !== null}
                        onClick={() => {
                          if (escrow.isPQProtected) onPqAuth({ kind: 'approve-release', escrow, index })
                          else void run(key, () => actions.approveAndRelease(escrow.id, index))
                        }}
                      >
                        {working ? <Loader2 className="size-3.5 animate-spin" /> : escrow.isPQProtected && <Fingerprint className="size-3.5" />}
                        Approve &amp; Release
                      </button>
                    )}
                    {role === 'employer' && status === 'APPROVED' && (
                      <button
                        type="button"
                        className={btnPrimary}
                        disabled={busy !== null}
                        onClick={() => {
                          if (escrow.isPQProtected) onPqAuth({ kind: 'release', escrow, index })
                          else void run(key, () => actions.releaseMilestone(escrow.id, index))
                        }}
                      >
                        {working ? <Loader2 className="size-3.5 animate-spin" /> : escrow.isPQProtected && <Fingerprint className="size-3.5" />}
                        Release Payout
                      </button>
                    )}
                    {role === 'contractor' && status === 'PENDING' && (
                      <button type="button" className={btnPrimary} disabled={busy !== null} onClick={() => onSubmitWork(escrow, index)}>
                        Submit Proof
                      </button>
                    )}
                    {role === 'contractor' && status === 'WORK SUBMITTED' && (() => {
                      const at = claimableAt(escrow, milestone)
                      if (at === null) return null
                      return at <= now ? (
                        <button
                          type="button"
                          className={btnPrimary}
                          disabled={busy !== null}
                          onClick={() => {
                            void run(key, () => actions.claimUncontested(escrow.id, index))
                          }}
                        >
                          {working && <Loader2 className="size-3.5 animate-spin" />}
                          Claim Payout
                        </button>
                      ) : (
                        <span className="text-xs font-medium text-zinc-400">Claimable in {formatDuration(at - now)}</span>
                      )
                    })()}
                    {role === 'employer' && status === 'WORK SUBMITTED' && (() => {
                      const at = claimableAt(escrow, milestone)
                      if (at === null) return null
                      return (
                        <span className="w-full text-right text-[0.6875rem] font-medium text-zinc-400">
                          {at <= now ? 'Review window ended' : `Review window ends in ${formatDuration(at - now)}`}
                        </span>
                      )
                    })()}
                    {role === 'contractor' && status === 'APPROVED' && (
                      <button
                        type="button"
                        className={btnPrimary}
                        disabled={busy !== null}
                        onClick={() => {
                          void run(key, () => actions.releaseMilestone(escrow.id, index))
                        }}
                      >
                        {working && <Loader2 className="size-3.5 animate-spin" />}
                        Claim Payout
                      </button>
                    )}
                    {status === 'RELEASED' && (
                      <button type="button" className={btnGhost} onClick={() => openInvoice(escrow, index)}>
                        <Receipt className="mr-1.5 size-3.5 text-neonLime" />
                        Invoice / Receipt
                      </button>
                    )}
                    <button type="button" className={btnGhost} onClick={() => onViewDetails(role)(escrow, index)}>
                      {status === 'RELEASED' || milestone.isWorkSubmitted ? 'View Proof' : 'Details'}
                    </button>
                  </div>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
