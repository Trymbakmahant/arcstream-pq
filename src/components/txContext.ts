import { createContext, useContext } from 'react'
import type { Hash } from 'viem'

export interface TxStep {
  label: string
  /** Optional pre-check; return true to skip this step (e.g. allowance already sufficient). */
  skipIf?: () => Promise<boolean>
  send: () => Promise<Hash>
}

export interface TxContextValue {
  runFlow: (title: string, steps: TxStep[]) => Promise<boolean>
}

export const TxContext = createContext<TxContextValue | null>(null)

export function useTx(): TxContextValue {
  const ctx = useContext(TxContext)
  if (!ctx) throw new Error('useTx must be used inside TxProvider')
  return ctx
}
