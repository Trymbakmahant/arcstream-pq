import { useMemo, useState, type ReactNode } from 'react'
import { InvoiceModal } from '@/components/dashboard/InvoiceModal'
import { InvoiceContext } from '@/components/dashboard/invoiceContext'
import type { EscrowView } from '@/hooks/useEscrows'

export function InvoiceProvider({ children }: { children: ReactNode }) {
  const [target, setTarget] = useState<{ escrow: EscrowView; index: number } | null>(null)
  const api = useMemo(() => ({ openInvoice: (escrow: EscrowView, index: number) => setTarget({ escrow, index }) }), [])
  return (
    <InvoiceContext.Provider value={api}>
      {children}
      <InvoiceModal target={target} onClose={() => setTarget(null)} />
    </InvoiceContext.Provider>
  )
}
