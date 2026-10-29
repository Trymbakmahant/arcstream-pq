import { useEffect, useRef, useState, type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Check, ChevronDown, TriangleAlert } from 'lucide-react'
import { NETWORK, NETWORKS, switchNetwork, type NetworkId } from '@/lib/network'

const ORDER: NetworkId[] = ['testnet', 'mainnet']

/** Dropdown pill that switches the whole app between Arc Testnet and Arc Mainnet (reloads the page). */
export function NetworkSwitcher({ wrongNetwork }: { wrongNetwork: boolean }) {
  const [open, setOpen] = useState(false)
  const [confirmMainnet, setConfirmMainnet] = useState(false)
  const root = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onDown = (event: MouseEvent) => {
      if (root.current && !root.current.contains(event.target as Node)) setOpen(false)
    }
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const choose = (id: NetworkId) => {
    setOpen(false)
    if (id === NETWORK.id) return
    if (id === 'mainnet') setConfirmMainnet(true)
    else switchNetwork(id)
  }

  return (
    <>
      <div ref={root} className="relative">
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          aria-haspopup="listbox"
          aria-expanded={open}
          className="inline-flex min-h-10 items-center gap-2 rounded-full border border-brandHighlight/10 bg-white px-4 font-mono text-xs font-medium text-brandHighlight hover:border-brandSecondary"
        >
          <span
            className={`size-2 rounded-full ${
              wrongNetwork ? 'border border-brandHighlight' : NETWORK.isMainnet ? 'bg-brandHighlight' : 'bg-brandSecondary'
            }`}
          />
          {wrongNetwork ? 'Wrong network' : `${NETWORK.label} (${NETWORK.chainId})`}
          <ChevronDown className={`size-4 transition-transform ${open ? 'rotate-180' : ''}`} />
        </button>

        {open && (
          <ul
            role="listbox"
            aria-label="Select network"
            className="absolute left-0 z-50 mt-2 w-72 rounded-2xl border border-brandHighlight/10 bg-white p-2 shadow-xl"
          >
            {ORDER.map((id) => {
              const net = NETWORKS[id]
              const active = id === NETWORK.id
              return (
                <li key={id} role="option" aria-selected={active}>
                  <button
                    type="button"
                    onClick={() => choose(id)}
                    className="flex min-h-12 w-full items-start gap-3 rounded-xl px-3 py-2 text-left hover:bg-brandSecondary/25"
                  >
                    <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
                      {active && <Check className="size-4 text-brandHighlight" />}
                    </span>
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold text-brandHighlight">
                        {net.label} <span className="font-mono text-xs font-normal">({net.chainId})</span>
                      </span>
                      <span className="block text-xs text-brandHighlight/70">
                        {net.isMainnet ? 'Real USDC. Transactions are irreversible.' : 'Test USDC. No real value.'}
                        {!net.vault && ' Vault not deployed yet.'}
                      </span>
                    </span>
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </div>

      <MainnetConfirm open={confirmMainnet} onClose={() => setConfirmMainnet(false)} />
    </>
  )
}

/** Real-funds confirmation shown before the app is pointed at Arc Mainnet. */
function MainnetConfirm({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[9800] flex items-center justify-center bg-brandHighlight/80 p-4 backdrop-blur-sm"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={() => onClose()}
          role="dialog"
          aria-modal="true"
          aria-label="Switch to Arc Mainnet"
        >
          <motion.div
            className="w-full max-w-md rounded-2xl border border-brandSecondary bg-brandMain p-6 shadow-2xl"
            initial={{ y: 16, scale: 0.98 }}
            animate={{ y: 0, scale: 1 }}
            exit={{ y: 16, scale: 0.98 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center gap-3">
              <span className="flex size-10 items-center justify-center rounded-full bg-brandHighlight text-brandMain">
                <TriangleAlert className="size-5" />
              </span>
              <h2 className="display text-xl font-bold text-brandHighlight">Switch to Arc Mainnet?</h2>
            </div>
            <p className="mt-4 text-sm text-brandHighlight/90">
              Arc Mainnet uses real USDC, and transactions cannot be reversed. ArcStreamVault has not had an
              independent professional audit. Use small amounts and review every address before you confirm.
            </p>
            {!NETWORKS.mainnet.vault && (
              <p className="mt-3 rounded-xl border border-brandHighlight/30 bg-white p-3 text-sm text-brandHighlight">
                ArcStreamVault is not deployed on Arc Mainnet yet, so the dashboard will be empty until it is.
              </p>
            )}
            <div className="mt-6 flex flex-wrap justify-end gap-3">
              <button type="button" className="btn-ghost" onClick={() => onClose()}>
                Stay on {NETWORK.label}
              </button>
              <button type="button" className="btn-primary" onClick={() => switchNetwork('mainnet')}>
                Switch to Arc Mainnet
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

/** A button that switches the app to another network, with the real-funds confirmation for Mainnet. */
export function SwitchNetworkButton({
  target,
  className,
  children,
}: {
  target: NetworkId
  className?: string
  children: ReactNode
}) {
  const [confirm, setConfirm] = useState(false)
  return (
    <>
      <button
        type="button"
        className={className}
        onClick={() => {
          if (target === 'mainnet') setConfirm(true)
          else switchNetwork(target)
        }}
      >
        {children}
      </button>
      <MainnetConfirm open={confirm} onClose={() => setConfirm(false)} />
    </>
  )
}

/** Slim reminder shown on every dashboard view while the app is pointed at Arc Mainnet. */
export function MainnetBanner() {
  if (!NETWORK.isMainnet) return null
  return (
    <div className="flex flex-wrap items-center justify-center gap-2 bg-brandHighlight px-4 py-2 text-center text-xs font-semibold text-brandMain">
      <TriangleAlert className="size-4" />
      Arc Mainnet: real USDC, irreversible transactions.
      <button type="button" className="underline underline-offset-4" onClick={() => switchNetwork('testnet')}>
        Switch to Testnet
      </button>
    </div>
  )
}
