import { useInvoice } from '@/components/dashboard/invoiceContext'
import { useNow } from '@/hooks/useNow'
import { claimableAt, formatDuration } from '@/lib/inspection'
import { useState } from 'react'
import { Loader2, ExternalLink, Fingerprint, Info, Receipt } from 'lucide-react'
import { addressUrl } from '@/contracts/vault'
import { milestoneStatus, type EscrowView } from '@/hooks/useEscrows'
import { useVaultActions } from '@/hooks/useVaultActions'
import { fmtUsdc, shortAddress } from '@/lib/money'
import { milestoneTitle } from '@/lib/text'
import { fingerprint as shortHash } from '@/lib/pq'
import type { PqAuthRequest } from '@/components/PqAuthModal'
import { ProgressBar, ProofViewer, StatusBadge } from '@/components/ui'

export type EscrowRole = 'employer' | 'contractor'

interface Props {
  escrow: EscrowView
  role: EscrowRole
  onSubmitWork: (escrow: EscrowView, index: number) => void
  onViewDetails: (escrow: EscrowView, index: number) => void
  onPqAuth: (request: PqAuthRequest) => void
}

export function EscrowCard({ escrow, role, onSubmitWork, onViewDetails, onPqAuth }: Props) {
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

  const approvedPending = escrow.milestones.reduce(
    (sum, m) => (m.isApproved && !m.isReleased && !escrow.isSettled ? sum + m.amount : sum),
    0n,
  )
  const hasSubmittedWaiting = escrow.milestones.some((m) => m.isWorkSubmitted && !m.isApproved)
  const hasPending = escrow.milestones.some((m) => !m.isWorkSubmitted && !m.isApproved)
  const counterparty = role === 'employer' ? escrow.contractor : escrow.employer
  const releasedCount = escrow.milestones.filter((m) => m.isReleased).length

  return (
    <article className="rounded-2xl border border-brandSecondary bg-brandSecondary/20 p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="label-caps text-brandHighlight/70">Escrow #{escrow.id.toString()}</p>
          <p className="mt-1 text-sm text-brandHighlight">
            {role === 'employer' ? 'Contractor' : 'Employer'}{' '}
            <a
              href={addressUrl(counterparty)}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 font-mono text-xs font-medium underline underline-offset-2"
            >
              {shortAddress(counterparty)}
              <ExternalLink className="size-3" />
            </a>
          </p>
        </div>
        <div className="text-right">
          <p className="label-caps text-brandHighlight/70">Total escrowed</p>
          <p className="display text-2xl font-bold tabular-nums text-brandHighlight">
            {fmtUsdc(escrow.totalDeposited)} <span className="text-sm font-medium">USDC</span>
          </p>
        </div>
      </div>

      <div className="mt-4">
        <ProgressBar total={escrow.totalDeposited} released={escrow.totalReleased} approved={approvedPending} />
        <p className="mt-2 flex flex-wrap justify-between gap-2 text-xs tabular-nums text-brandHighlight/80">
          <span>
            Paid out {fmtUsdc(escrow.totalReleased)} USDC ({releasedCount}/{escrow.milestoneCount} milestones)
          </span>
          {approvedPending > 0n && <span>Approved, awaiting payout {fmtUsdc(approvedPending)} USDC</span>}
        </p>
      </div>

      {escrow.isPQProtected && (
        <div className="mt-4 flex flex-wrap items-center gap-3 rounded-xl border border-brandHighlight bg-brandHighlight px-4 py-3 text-brandMain">
          <Fingerprint className="size-5 shrink-0 text-brandSecondary" />
          <div className="min-w-0 flex-1">
            <p className="text-xs font-bold tracking-[0.08em]">PQ-2FA SECURED</p>
            <p className="text-xs text-brandMain/80">Employer release and refund need Touch ID / Face ID</p>
          </div>
          <span
            className="rounded-full bg-brandSecondary px-3 py-1 font-mono text-xs font-semibold text-brandHighlight"
            title={escrow.pqCommitment}
          >
            PQ-ID {shortHash(escrow.pqCommitment)}
          </span>
        </div>
      )}

      {escrow.isSettled && (
        <p className="mt-4 flex items-start gap-2 rounded-2xl border border-brandSecondary bg-brandMain p-3 text-sm text-brandHighlight">
          <Info className="mt-0.5 size-4 shrink-0" />
          This escrow was settled by mutual cancellation. Each party claims their share through the contract.
        </p>
      )}
      {escrow.isTerminated && !escrow.isSettled && (
        <p className="mt-4 flex items-start gap-2 rounded-2xl border border-brandSecondary bg-brandMain p-3 text-sm text-brandHighlight">
          <Info className="mt-0.5 size-4 shrink-0" />
          This escrow was closed. Unapproved milestones were refunded to the employer. Approved milestones can still be paid out.
        </p>
      )}

      <ul className="mt-5 space-y-3">
        {escrow.milestones.map((m, index) => {
          const status = milestoneStatus(escrow, m)
          const key = `${escrow.id}-${index}`
          return (
            <li key={key} className="rounded-2xl border border-brandSecondary/80 bg-brandMain p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold text-brandHighlight">
                    {index + 1}. {milestoneTitle(m.description)}
                  </p>
                  <p className="mt-0.5 text-sm tabular-nums text-brandHighlight/80">{fmtUsdc(m.amount)} USDC</p>
                </div>
                <StatusBadge status={status} />
              </div>

              {m.isWorkSubmitted && m.workProofHash && (
                <div className="mt-3 rounded-xl bg-brandSecondary/25 p-3">
                  <p className="label-caps text-brandHighlight/70">Work proof</p>
                  <div className="mt-1">
                    <ProofViewer proof={m.workProofHash} compact />
                  </div>
                </div>
              )}

              <div className="mt-3 flex flex-wrap gap-2">
                <button type="button" className="btn-ghost" onClick={() => onViewDetails(escrow, index)}>
                  View Details
                </button>
                {role === 'employer' && status === 'WORK SUBMITTED' && (
                  <button
                    type="button"
                    className="btn-primary"
                    disabled={busy !== null}
                    onClick={() => {
                      void run(key, () => actions.approveMilestone(escrow.id, index))
                    }}
                  >
                    {busy === key && <Loader2 className="size-4 animate-spin" />}
                    Approve Milestone
                  </button>
                )}
                {role === 'employer' && status === 'PENDING' && (
                  <span className="text-xs text-brandHighlight/70">Waiting for the contractor to submit work.</span>
                )}
                {role === 'employer' && status === 'APPROVED' && (
                  <>
                    <button
                      type="button"
                      className="btn-primary"
                      disabled={busy !== null}
                      onClick={() => {
                        if (escrow.isPQProtected) onPqAuth({ kind: 'release', escrow, index })
                        else void run(key, () => actions.releaseMilestone(escrow.id, index))
                      }}
                    >
                      {busy === key && <Loader2 className="size-4 animate-spin" />}
                      {escrow.isPQProtected && <Fingerprint className="size-4" />}
                      Release Payout
                    </button>
                    <span className="self-center text-xs text-brandHighlight/70">
                      The contractor can also claim this themselves.
                    </span>
                  </>
                )}

                {role === 'contractor' && status === 'PENDING' && (
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={busy !== null}
                    onClick={() => onSubmitWork(escrow, index)}
                  >
                    Submit Work
                  </button>
                )}
                {role === 'contractor' && status === 'WORK SUBMITTED' && (
                  <>
                    <span className="self-center text-xs text-brandHighlight/70">Waiting for employer approval.</span>
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={busy !== null}
                      onClick={() => onSubmitWork(escrow, index)}
                    >
                      Update Proof
                    </button>
                  </>
                )}
                {role === 'contractor' && status === 'WORK SUBMITTED' && claimableAt(escrow, m) !== null && (
                  (claimableAt(escrow, m) ?? 0) <= now ? (
                    <button
                      type="button"
                      className="btn-primary w-full sm:w-auto sm:min-w-48"
                      disabled={busy !== null}
                      onClick={() => {
                        void run(key, () => actions.claimUncontested(escrow.id, index))
                      }}
                    >
                      {busy === key && <Loader2 className="size-4 animate-spin" />}
                      Claim Payout
                    </button>
                  ) : (
                    <span className="text-xs font-medium text-brandHighlight/70">
                      Claimable in {formatDuration((claimableAt(escrow, m) ?? 0) - now)}
                    </span>
                  )
                )}
                {status === 'RELEASED' && (
                  <button type="button" className="btn-ghost w-full sm:w-auto" onClick={() => openInvoice(escrow, index)}>
                    <Receipt className="size-4" />
                    Invoice / Receipt
                  </button>
                )}
                {role === 'contractor' && status === 'APPROVED' && (
                  <button
                    type="button"
                    className="btn-primary w-full sm:w-auto sm:min-w-48"
                    disabled={busy !== null}
                    onClick={() => {
                      void run(key, () => actions.releaseMilestone(escrow.id, index))
                    }}
                  >
                    {busy === key && <Loader2 className="size-4 animate-spin" />}
                    Claim Payout
                  </button>
                )}
              </div>
            </li>
          )
        })}
      </ul>

      {role === 'employer' && !escrow.isTerminated && hasPending && (
        <div className="mt-5 flex flex-wrap items-center gap-3 border-t border-brandSecondary pt-4">
          <button
            type="button"
            className="btn-ghost"
            disabled={busy !== null || hasSubmittedWaiting}
            onClick={() => {
              if (escrow.isPQProtected) onPqAuth({ kind: 'refund', escrow })
              else void run(`refund-${escrow.id}`, () => actions.refundRemaining(escrow.id))
            }}
          >
            {busy === `refund-${escrow.id}` && <Loader2 className="size-4 animate-spin" />}
            Refund Unstarted Milestones
          </button>
          {hasSubmittedWaiting && (
            <span className="text-xs text-brandHighlight/70">
              Refunds are blocked while submitted work is waiting for your approval.
            </span>
          )}
        </div>
      )}
    </article>
  )
}
