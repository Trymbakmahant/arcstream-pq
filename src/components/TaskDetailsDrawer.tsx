import { useInvoice } from '@/components/dashboard/invoiceContext'
import { useNow } from '@/hooks/useNow'
import { claimableAt, formatDuration } from '@/lib/inspection'
import { useEffect, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ExternalLink, Loader2, Receipt, X } from 'lucide-react'
import { addressUrl } from '@/contracts/vault'
import { milestoneStatus, type EscrowView } from '@/hooks/useEscrows'
import { useSubmissionTime } from '@/hooks/useSubmissionTime'
import { useVaultActions } from '@/hooks/useVaultActions'
import { fmtUsdc, shortAddress } from '@/lib/money'
import { milestoneTitle } from '@/lib/text'
import type { EscrowRole } from '@/components/EscrowCard'
import { RichText } from '@/components/RichText'
import type { PqAuthRequest } from '@/components/PqAuthModal'
import { ProofViewer, StatusBadge } from '@/components/ui'

export interface DetailsTarget {
  escrowId: bigint
  index: number
  role: EscrowRole
}

interface Props {
  target: DetailsTarget | null
  escrow: EscrowView | undefined
  onClose: () => void
  onSubmitWork: (escrow: EscrowView, index: number) => void
  onPqAuth: (request: PqAuthRequest) => void
}

export function TaskDetailsDrawer({ target, escrow, onClose, onSubmitWork, onPqAuth }: Props) {
  useEffect(() => {
    if (!target) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [target, onClose])

  const open = !!target && !!escrow && !!escrow.milestones[target.index]

  return (
    <AnimatePresence>
      {open && target && escrow && (
        <motion.div
          key="task-details"
          className="fixed inset-0 z-[8000] flex justify-end bg-brandHighlight/60 backdrop-blur-sm"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
        >
          <motion.aside
            role="dialog"
            aria-modal="true"
            aria-label="Milestone details"
            className="flex h-full w-full max-w-lg flex-col overflow-y-auto border-l border-brandSecondary bg-brandMain"
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={{ type: 'spring', stiffness: 360, damping: 38 }}
            onClick={(e) => e.stopPropagation()}
          >
            <DrawerBody
              target={target}
              escrow={escrow}
              onClose={onClose}
              onSubmitWork={onSubmitWork}
              onPqAuth={onPqAuth}
            />
          </motion.aside>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function DrawerBody({
  target,
  escrow,
  onClose,
  onSubmitWork,
  onPqAuth,
}: {
  target: DetailsTarget
  escrow: EscrowView
  onClose: () => void
  onSubmitWork: (escrow: EscrowView, index: number) => void
  onPqAuth: (request: PqAuthRequest) => void
}) {
  const actions = useVaultActions()
  const [busy, setBusy] = useState(false)
  const milestone = escrow.milestones[target.index]
  const status = milestoneStatus(escrow, milestone)
  const submitted = milestone.isWorkSubmitted && !!milestone.workProofHash
  const submission = useSubmissionTime(escrow.id, target.index, milestone.workProofHash, submitted)
  const counterparty = target.role === 'employer' ? escrow.contractor : escrow.employer
  const now = useNow()
  const { openInvoice } = useInvoice()
  const claimAt = claimableAt(escrow, milestone)
  const windowOver = claimAt !== null && claimAt <= now

  const run = async (fn: () => Promise<boolean>) => {
    setBusy(true)
    try {
      await fn()
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <div className="sticky top-0 z-10 flex items-start justify-between gap-4 border-b border-brandSecondary bg-brandMain p-6">
        <div className="min-w-0">
          <p className="label-caps text-brandHighlight/70">
            Escrow #{escrow.id.toString()} / Milestone {target.index + 1}
          </p>
          <h2 className="display mt-1 text-balance text-xl font-bold text-brandHighlight">
            {milestoneTitle(milestone.description)}
          </h2>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="flex size-11 shrink-0 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
          aria-label="Close details"
        >
          <X className="size-5" />
        </button>
      </div>

      <div className="flex-1 space-y-6 p-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <StatusBadge status={status} />
          <p className="display text-2xl font-black tabular-nums text-brandHighlight">
            {fmtUsdc(milestone.amount)} <span className="text-sm font-medium">USDC</span>
          </p>
        </div>

        <section>
          <h3 className="label-caps text-brandHighlight/70">Deliverables and scope</h3>
          <div className="mt-2 rounded-2xl border border-brandHighlight/15 bg-white p-4">
            <RichText text={milestone.description || 'No description was provided.'} />
          </div>
        </section>

        <section>
          <h3 className="label-caps text-brandHighlight/70">Work proof</h3>
          {submitted ? (
            <div className="mt-2 space-y-2 rounded-2xl border border-brandSecondary bg-brandSecondary/25 p-4">
              <ProofViewer proof={milestone.workProofHash} />
              <p className="text-xs tabular-nums text-brandHighlight/80">
                {submission.isLoading
                  ? 'Looking up submission time...'
                  : submission.data
                    ? `Submitted ${new Date(submission.data * 1000).toLocaleString()}`
                    : 'Submission time unavailable'}
              </p>
            </div>
          ) : (
            <p className="mt-2 rounded-2xl border border-dashed border-brandSecondary p-4 text-sm text-brandHighlight/80">
              {target.role === 'employer'
                ? 'The contractor has not submitted work for this milestone yet.'
                : 'You have not submitted work for this milestone yet.'}
            </p>
          )}
        </section>

        {claimAt !== null && (
          <section>
            <h3 className="label-caps text-brandHighlight/70">Review window</h3>
            <div className="mt-2 rounded-2xl border border-brandSecondary bg-white p-4 text-sm text-brandHighlight">
              <p className="font-semibold tabular-nums">
                {windowOver ? 'The review window has ended.' : `Ends in ${formatDuration(claimAt - now)}`}
                <span className="font-normal text-brandHighlight/70">
                  {' '}
                  ({new Date(claimAt * 1000).toLocaleString()})
                </span>
              </p>
              <p className="mt-1 text-xs text-brandHighlight/80">
                {target.role === 'employer'
                  ? 'Approve before the window ends. Afterwards the contractor can claim this milestone without your approval.'
                  : windowOver
                    ? 'The employer did not approve in time, so you can claim this milestone now.'
                    : 'If the employer does not approve before the window ends, you can claim this milestone yourself. Updating your proof restarts the window.'}
              </p>
            </div>
          </section>
        )}

        <p className="text-xs text-brandHighlight/70">
          {target.role === 'employer' ? 'Contractor' : 'Employer'}{' '}
          <a
            href={addressUrl(counterparty)}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 font-mono font-medium underline underline-offset-2"
          >
            {shortAddress(counterparty)}
            <ExternalLink className="size-3" />
          </a>
        </p>
      </div>

      <div className="sticky bottom-0 flex flex-wrap gap-3 border-t border-brandSecondary bg-brandMain p-6">
        {target.role === 'employer' && status === 'WORK SUBMITTED' && (
          <button
            type="button"
            className="btn-primary flex-1"
            disabled={busy}
            onClick={() => {
              void run(() => actions.approveMilestone(escrow.id, target.index))
            }}
          >
            {busy && <Loader2 className="size-4 animate-spin" />}
            Approve Milestone
          </button>
        )}
        {target.role === 'employer' && status === 'APPROVED' && (
          <button
            type="button"
            className="btn-primary flex-1"
            disabled={busy}
            onClick={() => {
              if (escrow.isPQProtected) onPqAuth({ kind: 'release', escrow, index: target.index })
              else void run(() => actions.releaseMilestone(escrow.id, target.index))
            }}
          >
            {busy && <Loader2 className="size-4 animate-spin" />}
            Release Payout
          </button>
        )}
        {target.role === 'contractor' && status === 'WORK SUBMITTED' && windowOver && (
          <button
            type="button"
            className="btn-primary flex-1"
            disabled={busy}
            onClick={() => {
              void run(() => actions.claimUncontested(escrow.id, target.index))
            }}
          >
            {busy && <Loader2 className="size-4 animate-spin" />}
            Claim Payout
          </button>
        )}
        {target.role === 'contractor' && (status === 'PENDING' || status === 'WORK SUBMITTED') && (
          <button type="button" className="btn-ghost flex-1" onClick={() => onSubmitWork(escrow, target.index)}>
            {status === 'PENDING' ? 'Submit Work' : 'Update Proof'}
          </button>
        )}
        {target.role === 'contractor' && status === 'APPROVED' && (
          <button
            type="button"
            className="btn-primary flex-1"
            disabled={busy}
            onClick={() => {
              void run(() => actions.releaseMilestone(escrow.id, target.index))
            }}
          >
            {busy && <Loader2 className="size-4 animate-spin" />}
            Claim Payout
          </button>
        )}
        {status === 'RELEASED' && (
          <button type="button" className="btn-primary flex-1" onClick={() => openInvoice(escrow, target.index)}>
            <Receipt className="size-4" />
            Download Invoice / Receipt
          </button>
        )}
        <button type="button" className="btn-ghost" onClick={onClose}>
          Close
        </button>
      </div>
    </>
  )
}
