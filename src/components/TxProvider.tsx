import { useCallback, useMemo, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAccount, usePublicClient, useSwitchChain } from 'wagmi'
import type { Hash } from 'viem'
import { AnimatePresence, motion } from 'framer-motion'
import { toast } from 'sonner'
import { Check, ExternalLink, Loader2, TriangleAlert, X } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { txUrl } from '@/contracts/vault'
import { NETWORK } from '@/lib/network'
import { isUserRejection, parseOnchainError } from '@/lib/errors'
import { TxContext, type TxStep } from '@/components/txContext'

type StepStatus = 'pending' | 'wallet' | 'confirming' | 'done' | 'skipped' | 'error'

interface StepState {
  label: string
  status: StepStatus
  hash?: Hash
}

interface FlowState {
  title: string
  steps: StepState[]
  error?: string
  rawError?: string
  finished: boolean
}

export function TxProvider({ children }: { children: ReactNode }) {
  const [flow, setFlow] = useState<FlowState | null>(null)
  const queryClient = useQueryClient()
  const publicClient = usePublicClient({ chainId: ARC_CHAIN_ID })
  const { chainId } = useAccount()
  const { switchChainAsync } = useSwitchChain()

  const runFlow = useCallback(
    async (title: string, steps: TxStep[]): Promise<boolean> => {
      if (!publicClient) return false
      const states: StepState[] = steps.map((s) => ({ label: s.label, status: 'pending' }))
      const update = (index: number, patch: Partial<StepState>, error?: string) => {
        states[index] = { ...states[index], ...patch }
        setFlow({ title, steps: states.map((s) => ({ ...s })), error, finished: false })
      }
      setFlow({ title, steps: states.map((s) => ({ ...s })), finished: false })

      let activeIndex = 0
      try {
        if (chainId !== ARC_CHAIN_ID) {
          await switchChainAsync({ chainId: ARC_CHAIN_ID })
        }
        for (let i = 0; i < steps.length; i++) {
          activeIndex = i
          if (steps[i].skipIf && (await steps[i].skipIf?.())) {
            update(i, { status: 'skipped' })
            continue
          }
          update(i, { status: 'wallet' })
          const hash = await steps[i].send()
          update(i, { status: 'confirming', hash })
          const receipt = await publicClient.waitForTransactionReceipt({ hash })
          if (receipt.status !== 'success') {
            throw new Error('Transaction reverted')
          }
          update(i, { status: 'done', hash })
        }
        await Promise.all([
          queryClient.invalidateQueries({ queryKey: ['escrows'] }),
          queryClient.invalidateQueries({ queryKey: ['usdc-balance'] }),
        ])
        setFlow({ title, steps: states.map((s) => ({ ...s })), finished: true })
        return true
      } catch (error) {
        console.error('🚨 [ArcStream Tx Error]:', error)
        if (error instanceof Error) {
          console.error('🚨 Error Message:', error.message)
          if ('cause' in error && error.cause) {
            console.error('🚨 Error Cause:', error.cause)
          }
        }
        if (isUserRejection(error)) {
          setFlow(null)
          toast('Transaction cancelled.')
          return false
        }
        const parsed = parseOnchainError(error)
        const rawMsg = error instanceof Error ? error.message : String(error)
        update(activeIndex, { status: 'error' }, parsed)
        setFlow((current) => (current ? { ...current, error: parsed, rawError: rawMsg, finished: true } : current))
        return false
      }
    },
    [chainId, publicClient, queryClient, switchChainAsync],
  )

  const value = useMemo(() => ({ runFlow }), [runFlow])

  const hashes = (flow?.steps ?? []).map((s) => s.hash).filter((h): h is Hash => !!h)
  const lastHash: Hash | undefined = hashes[hashes.length - 1]

  return (
    <TxContext.Provider value={value}>
      {children}
      <AnimatePresence>
        {flow && (
          <motion.div
            className="fixed inset-0 z-[10000] flex items-center justify-center bg-black/85 p-4 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            role="dialog"
            aria-modal="true"
            aria-label="Transaction progress"
          >
            <motion.div
              className="neu-card w-full max-w-md rounded-3xl border border-white/10 p-6 shadow-2xl"
              initial={{ y: 16, scale: 0.98 }}
              animate={{ y: 0, scale: 1 }}
              exit={{ y: 16, scale: 0.98 }}
              transition={{ type: 'spring', stiffness: 380, damping: 32 }}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="label-caps font-semibold text-neonLime">{NETWORK.label}</span>
                    <span className="neu-sunken rounded border border-white/5 px-1.5 py-0.5 font-mono text-[11px] text-zinc-400">
                      ID: {NETWORK.chainId}
                    </span>
                    <span className="neu-sunken rounded border border-white/5 px-1.5 py-0.5 font-mono text-[10px] text-zinc-400" title={NETWORK.rpcUrl}>
                      RPC: {NETWORK.rpcUrl.replace('https://', '')}
                    </span>
                  </div>
                  <h2 className="display mt-1.5 text-xl font-bold text-white tracking-tight">{flow.title}</h2>
                </div>
                <button
                  type="button"
                  onClick={() => setFlow(null)}
                  className="neu-card flex size-10 items-center justify-center rounded-xl border border-white/5 text-zinc-400 hover:text-white"
                  aria-label="Close"
                  title="Close modal"
                >
                  <X className="size-5" />
                </button>
              </div>

              <ol className="mt-5 space-y-3">
                {flow.steps.map((step, index) => (
                  <li
                    key={`${step.label}-${index}`}
                    className="neu-sunken flex items-center gap-3 rounded-2xl border border-white/5 p-3"
                  >
                    <StepIcon status={step.status} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-semibold text-white">{step.label}</p>
                      <p className="text-xs text-zinc-400">{stepCopy(step.status)}</p>
                    </div>
                    {step.hash && (
                      <a
                        href={txUrl(step.hash)}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex min-h-11 items-center gap-1 text-xs font-semibold text-neonLime underline underline-offset-2"
                      >
                        Tx <ExternalLink className="size-3" />
                      </a>
                    )}
                  </li>
                ))}
              </ol>

              {flow.error && (
                <div className="neu-sunken mt-4 rounded-2xl border border-neonPink/40 p-3.5 text-sm font-medium text-neonPink shadow-glow-pink">
                  <p className="flex items-start gap-2">
                    <TriangleAlert className="mt-0.5 size-4 shrink-0 text-neonPink" />
                    <span>{flow.error}</span>
                  </p>
                  {flow.rawError && (
                    <details className="mt-2.5 border-t border-white/10 pt-2 text-xs">
                      <summary className="cursor-pointer font-semibold opacity-80 hover:opacity-100 text-zinc-300">
                        View raw error details (also logged to console)
                      </summary>
                      <pre className="neu-sunken mt-2 max-h-40 overflow-auto rounded-lg border border-white/5 p-2.5 font-mono text-[11px] leading-relaxed break-all whitespace-pre-wrap select-all text-zinc-300">
                        {flow.rawError}
                      </pre>
                    </details>
                  )}
                </div>
              )}

              {lastHash && (
                <a
                  href={txUrl(lastHash)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-primary mt-5 flex min-h-11 items-center justify-center gap-2 rounded-xl text-sm font-semibold"
                >
                  View on {NETWORK.label} Explorer <ExternalLink className="size-4" />
                </a>
              )}

              {flow.finished && (
                <button type="button" onClick={() => setFlow(null)} className="btn-ghost mt-3 w-full">
                  {flow.error ? 'Close' : 'Done'}
                </button>
              )}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </TxContext.Provider>
  )
}

function stepCopy(status: StepStatus): string {
  switch (status) {
    case 'pending':
      return 'Waiting'
    case 'wallet':
      return 'Confirm in your wallet'
    case 'confirming':
      return 'Confirming onchain'
    case 'done':
      return 'Confirmed'
    case 'skipped':
      return 'Already satisfied'
    case 'error':
      return 'Failed'
  }
}

function StepIcon({ status }: { status: StepStatus }) {
  const base = 'flex size-8 shrink-0 items-center justify-center rounded-lg'
  if (status === 'wallet' || status === 'confirming') {
    return (
      <span className={`${base} neu-card border border-neonLime/40 text-neonLime shadow-glow-lime`}>
        <Loader2 className="size-4 animate-spin" />
      </span>
    )
  }
  if (status === 'done' || status === 'skipped') {
    return (
      <span className={`${base} neu-card border border-neonLime/40 text-neonLime shadow-glow-lime`}>
        <Check className="size-4" />
      </span>
    )
  }
  if (status === 'error') {
    return (
      <span className={`${base} neu-card border border-neonPink/40 text-neonPink shadow-glow-pink`}>
        <TriangleAlert className="size-4" />
      </span>
    )
  }
  return <span className={`${base} neu-sunken border border-white/5 text-zinc-600`} />
}
