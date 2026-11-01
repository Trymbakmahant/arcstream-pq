import { useEffect } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { X } from 'lucide-react'
import { NETWORK } from '@/lib/network'
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
          className="fixed inset-0 z-[7000] flex items-center justify-center bg-black/80 p-3 backdrop-blur-sm sm:p-6"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          role="dialog"
          aria-modal="true"
          aria-label="Create escrow"
        >
          <motion.div
            className="neu-card flex max-h-[calc(100dvh-1.5rem)] w-full max-w-2xl flex-col overflow-hidden rounded-3xl border border-white/10 shadow-2xl sm:max-h-[calc(100dvh-3rem)]"
            initial={{ y: 16, scale: 0.98 }}
            animate={{ y: 0, scale: 1 }}
            exit={{ y: 16, scale: 0.98 }}
            transition={{ type: 'spring', stiffness: 380, damping: 34 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-start justify-between gap-4 border-b border-white/5 bg-[#0a0d14]/70 px-6 py-5">
              <div>
                <h2 className="display text-xl font-bold text-white tracking-tight">Create Escrow</h2>
                <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
                  <span className="neu-sunken inline-flex items-center gap-1.5 rounded-full border border-white/5 px-2.5 py-0.5 font-medium text-zinc-300 font-mono">
                    <span className={`size-2 rounded-full ${NETWORK.isMainnet ? 'bg-emerald-500 shadow-[0_0_8px_#10b981]' : 'bg-neonLime shadow-[0_0_8px_#d4ff3f]'}`} />
                    {NETWORK.label}
                  </span>
                  <span className="neu-sunken rounded-md border border-white/5 px-2 py-0.5 font-mono text-[11px] text-zinc-400">
                    Network ID: <strong className="text-white">{NETWORK.chainId}</strong>
                  </span>
                  <span className="neu-sunken rounded-md border border-white/5 px-2 py-0.5 font-mono text-[11px] text-zinc-400" title={NETWORK.rpcUrl}>
                    RPC: <strong className="text-white">{NETWORK.rpcUrl.replace('https://', '')}</strong>
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="neu-card flex size-10 items-center justify-center rounded-xl border border-white/5 text-zinc-400 hover:text-white"
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
