import { createContext, useContext } from 'react'
import type { EscrowView } from '@/hooks/useEscrows'

export interface InvoiceApi {
  /** Opens the invoice / receipt for a released milestone. */
  openInvoice: (escrow: EscrowView, index: number) => void
}

export const InvoiceContext = createContext<InvoiceApi | null>(null)

export function useInvoice(): InvoiceApi {
  const ctx = useContext(InvoiceContext)
  if (!ctx) throw new Error('useInvoice must be used inside InvoiceProvider')
  return ctx
}
