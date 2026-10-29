import { useEffect } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { X } from 'lucide-react'
import { CreateEscrowCard } from '@/components/CreateEscrowCard'

interface Props {
  open: boolean
  onClose: () => void
}

export function CreateEscrowModal({ open, onClose }: Props) {
  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[7000] flex items-start justify-center overflow-y-auto bg-brandHighlight/60 p-4 backdrop-blur-sm sm:items-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          role="dialog"
          aria-modal="true"
          aria-label="Create escrow"
        >
          <motion.div
            className="relative my-4 w-full max-w-2xl"
            initial={{ y: 20 }}
            animate={{ y: 0 }}
            exit={{ y: 20 }}
            transition={{ type: 'spring', stiffness: 380, damping: 34 }}
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={onClose}
              className="absolute right-3 top-3 z-10 flex size-11 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
              aria-label="Close"
            >
              <X className="size-5" />
            </button>
            <div className="rounded-2xl bg-brandMain">
              <CreateEscrowCard onCreated={onClose} />
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
