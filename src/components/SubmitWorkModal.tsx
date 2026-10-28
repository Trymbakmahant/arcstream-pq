import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { X } from 'lucide-react'
import type { EscrowView } from '@/hooks/useEscrows'

const MAX_PROOF = 256
const encoder = new TextEncoder()

interface Target {
  escrow: EscrowView
  index: number
}

interface Props {
  target: Target | null
  onClose: () => void
  onSubmit: (escrow: EscrowView, index: number, proof: string) => void
}

export function SubmitWorkModal({ target, onClose, onSubmit }: Props) {
  return (
    <AnimatePresence>
      {target && (
        <motion.div
          key="submit-work"
          className="fixed inset-0 z-[9000] flex items-end justify-center bg-brandHighlight/70 p-4 backdrop-blur-sm sm:items-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          role="dialog"
          aria-modal="true"
          aria-label="Submit work"
        >
          <SubmitForm
            key={`${target.escrow.id.toString()}-${target.index}`}
            target={target}
            onClose={onClose}
            onSubmit={onSubmit}
          />
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function SubmitForm({ target, onClose, onSubmit }: { target: Target; onClose: () => void; onSubmit: Props['onSubmit'] }) {
  const [proof, setProof] = useState(target.escrow.milestones[target.index]?.workProofHash ?? '')
  const trimmed = proof.trim()
  const bytes = encoder.encode(trimmed).length
  const tooLong = bytes > MAX_PROOF
  const valid = trimmed.length > 0 && !tooLong

  return (
    <motion.form
      className="w-full max-w-md rounded-2xl border border-brandSecondary bg-brandMain p-6"
      initial={{ y: 24 }}
      animate={{ y: 0 }}
      exit={{ y: 24 }}
      transition={{ type: 'spring', stiffness: 380, damping: 32 }}
      onClick={(e) => e.stopPropagation()}
      onSubmit={(e) => {
        e.preventDefault()
        if (valid) onSubmit(target.escrow, target.index, trimmed)
      }}
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="label-caps text-brandHighlight/70">
            Escrow #{target.escrow.id.toString()} / Milestone {target.index + 1}
          </p>
          <h2 className="display mt-1 text-xl font-bold text-brandHighlight">Submit work</h2>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="flex size-11 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
          aria-label="Close"
        >
          <X className="size-5" />
        </button>
      </div>

      <p className="mt-3 text-sm text-brandHighlight/80">{target.escrow.milestones[target.index]?.description}</p>

      <label htmlFor="proof" className="label-caps mt-5 block text-brandHighlight/70">
        Proof URL, IPFS CID or Git commit hash
      </label>
      <textarea
        id="proof"
        className="field mt-2 min-h-24 resize-none font-mono text-sm"
        placeholder="https://github.com/org/repo/commit/abc123 or ipfs://bafy..."
        value={proof}
        onChange={(e) => setProof(e.target.value)}
        autoFocus
      />
      <p className="mt-1 flex justify-between text-xs tabular-nums text-brandHighlight/70">
        <span>{tooLong ? 'Proof must be 256 bytes or fewer.' : 'Shared with the employer onchain.'}</span>
        <span>
          {bytes}/{MAX_PROOF}
        </span>
      </p>

      <div className="mt-5 flex gap-3">
        <button type="button" className="btn-ghost flex-1" onClick={onClose}>
          Cancel
        </button>
        <button type="submit" className="btn-primary flex-1" disabled={!valid}>
          Submit Work
        </button>
      </div>
    </motion.form>
  )
}
