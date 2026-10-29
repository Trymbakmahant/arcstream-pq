import { useEffect } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { X } from 'lucide-react'
import { CreateEscrowCard } from '@/components/CreateEscrowCard'

interface Props {
  open: boolean
  onClose: () => void
  onFund: () => void
}

export function CreateEscrowModal({ open, onClose, onFund }: Props) {
  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    // Keep the page behind the modal from scrolling while it is open.
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = previousOverflow
    }
  }, [open, onClose])

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[7000] flex items-center justify-center bg-brandHighlight/60 p-3 backdrop-blur-sm sm:p-6"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          role="dialog"
          aria-modal="true"
          aria-label="Create escrow"
        >
          <motion.div
            className="flex max-h-[calc(100dvh-1.5rem)] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-brandSecondary bg-brandMain shadow-2xl sm:max-h-[calc(100dvh-3rem)]"
            initial={{ y: 16, scale: 0.98 }}
            animate={{ y: 0, scale: 1 }}
            exit={{ y: 16, scale: 0.98 }}
            transition={{ type: 'spring', stiffness: 380, damping: 34 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-center justify-between gap-4 border-b border-brandSecondary bg-brandMain px-6 py-3">
              <h2 className="display text-xl font-bold text-brandHighlight">Create Escrow</h2>
              <button
                type="button"
                onClick={onClose}
                className="flex size-11 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
                aria-label="Close"
              >
                <X className="size-5" />
              </button>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
              <CreateEscrowCard embedded onCreated={onClose} onFund={onFund} />
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
