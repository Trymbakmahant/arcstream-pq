import { useEffect } from 'react'
import { createPortal } from 'react-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { Printer, X } from 'lucide-react'
import { InvoiceSheet } from '@/components/dashboard/InvoiceSheet'
import type { EscrowView } from '@/hooks/useEscrows'
import { useSettlement } from '@/hooks/useSettlement'

interface Props {
  target: { escrow: EscrowView; index: number } | null
  onClose: () => void
}

/**
 * Print-ready invoice / receipt for a released milestone. It renders into document.body as #invoice-root so
 * the print stylesheet (src/index.css) can hide the dashboard and print only the invoice.
 */
export function InvoiceModal({ target, onClose }: Props) {
  useEffect(() => {
    if (!target) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    document.body.classList.add('invoice-open')
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = previousOverflow
      document.body.classList.remove('invoice-open')
    }
  }, [target, onClose])

  return createPortal(
    <div id="invoice-root">
      <AnimatePresence>{target && <InvoiceDialog key="invoice" target={target} onClose={onClose} />}</AnimatePresence>
    </div>,
    document.body,
  )
}

function InvoiceDialog({ target, onClose }: { target: { escrow: EscrowView; index: number }; onClose: () => void }) {
  const { escrow, index } = target
  const settlement = useSettlement(escrow.id, index, true)

  return (
    <motion.div
      className="invoice-overlay fixed inset-0 z-[9000] flex items-center justify-center bg-brandHighlight/70 p-3 backdrop-blur-sm sm:p-6"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label="Invoice and receipt"
    >
      <motion.div
        className="invoice-panel flex max-h-[calc(100dvh-1.5rem)] w-full max-w-3xl flex-col overflow-hidden rounded-2xl border border-brandSecondary bg-brandMain shadow-2xl sm:max-h-[calc(100dvh-3rem)]"
        initial={{ y: 16, scale: 0.98 }}
        animate={{ y: 0, scale: 1 }}
        exit={{ y: 16, scale: 0.98 }}
        transition={{ type: 'spring', stiffness: 380, damping: 34 }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="no-print flex shrink-0 items-center justify-between gap-3 border-b border-brandSecondary px-5 py-3">
          <h2 className="display text-lg font-bold text-brandHighlight">Invoice / Receipt</h2>
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="btn-primary min-h-11"
              onClick={() => {
                window.print()
              }}
            >
              <Printer className="size-4" />
              Print / Save PDF
            </button>
            <button
              type="button"
              onClick={onClose}
              className="flex size-11 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
              aria-label="Close invoice"
            >
              <X className="size-5" />
            </button>
          </div>
        </div>
        <div className="invoice-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain">
          <InvoiceSheet escrow={escrow} index={index} settlement={settlement.data} loading={settlement.isLoading} />
        </div>
      </motion.div>
    </motion.div>
  )
}
