import { useEffect } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { useAccount } from 'wagmi'
import { toast } from 'sonner'
import { ArrowUpRight, Copy, Droplets, Landmark, Loader2, RefreshCw, X } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { FAUCET_URL } from '@/contracts/vault'
import { SwitchNetworkButton } from '@/components/NetworkSwitcher'
import { NETWORK } from '@/lib/network'
import { useUsdcBalance } from '@/hooks/useUsdc'
import { fmtUsdc } from '@/lib/money'
import { OnrampSection } from '@/components/dashboard/OnrampSection'

interface Props {
  open: boolean
  onClose: () => void
}

export function FundModal({ open, onClose }: Props) {
  const { address, isConnected } = useAccount()
  const { data: balance, refetch, isFetching } = useUsdcBalance()

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  const copy = async () => {
    if (!address) return
    try {
      await navigator.clipboard.writeText(address)
      toast.success('Wallet address copied')
    } catch {
      toast.error('Could not copy. Select the address and copy it manually.')
    }
  }

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[7500] flex items-start justify-center overflow-y-auto bg-brandHighlight/60 p-4 backdrop-blur-sm sm:items-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          role="dialog"
          aria-modal="true"
          aria-label="Fund with USDC"
        >
          <motion.div
            className="relative my-4 w-full max-w-lg rounded-2xl border border-brandSecondary bg-brandMain p-6 shadow-2xl"
            initial={{ y: 20 }}
            animate={{ y: 0 }}
            exit={{ y: 20 }}
            transition={{ type: 'spring', stiffness: 380, damping: 34 }}
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={onClose}
              className="absolute right-3 top-3 flex size-11 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
              aria-label="Close"
            >
              <X className="size-5" />
            </button>

            <p className="label-caps text-brandHighlight/70">Fund your wallet</p>
            <h2 className="display mt-1 text-2xl font-bold text-brandHighlight">Fund with USDC</h2>
            <p className="mt-2 text-sm text-brandHighlight/80">
              On Arc, USDC is both your balance and your gas, so one balance covers escrow deposits and fees.
            </p>

            <div className="mt-5 rounded-xl border border-brandSecondary bg-white p-4">
              <p className="label-caps text-brandHighlight/60">Your wallet</p>
              {isConnected && address ? (
                <>
                  <p className="mt-1 break-all font-mono text-sm text-brandHighlight">{address}</p>
                  <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
                    <p className="text-sm tabular-nums text-brandHighlight">
                      Balance:{' '}
                      <strong>{balance !== undefined ? `${fmtUsdc(balance)} USDC` : '...'}</strong>
                    </p>
                    <div className="flex gap-2">
                      <button type="button" className="btn-ghost min-h-11" onClick={() => void copy()}>
                        <Copy className="size-4" />
                        Copy address
                      </button>
                      <button
                        type="button"
                        className="btn-ghost min-h-11"
                        onClick={() => void refetch()}
                        disabled={isFetching}
                      >
                        {isFetching ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
                        Refresh
                      </button>
                    </div>
                  </div>
                </>
              ) : (
                <p className="mt-1 text-sm text-brandHighlight/80">Connect a wallet to see your address and balance.</p>
              )}
            </div>

            {!NETWORK.isMainnet && (
            <section className="mt-4 rounded-xl border border-brandSecondary bg-brandSecondary/20 p-4">
              <h3 className="flex items-center gap-2 font-semibold text-brandHighlight">
                <Droplets className="size-4" />
                Arc Testnet (chain {ARC_CHAIN_ID}): free test USDC
              </h3>
              <ol className="mt-2 list-decimal space-y-1 pl-5 text-sm text-brandHighlight/90">
                <li>Copy your wallet address above.</li>
                <li>Open the Circle Faucet, choose Arc Testnet and USDC, and paste your address.</li>
                <li>Come back here and press Refresh. Test USDC has no real value.</li>
              </ol>
              <a
                href={FAUCET_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-primary mt-3 inline-flex min-h-11"
              >
                Open Circle Faucet
                <ArrowUpRight className="size-4" />
              </a>
            </section>
            )}

            <OnrampSection onDone={() => void refetch()} />

            <section className="mt-4 rounded-xl border border-brandHighlight/15 bg-white p-4">
              <h3 className="flex items-center gap-2 font-semibold text-brandHighlight">
                <Landmark className="size-4" />
                {NETWORK.isMainnet ? 'You are on Arc Mainnet' : 'Arc Mainnet: real USDC'}
              </h3>
              <p className="mt-2 text-sm text-brandHighlight/80">
                {NETWORK.isMainnet
                  ? 'Escrows here use real USDC from your wallet. Transactions involve real funds and cannot be reversed. Switch back to Arc Testnet to practice with free test USDC.'
                  : 'This app is on Arc Testnet. To use real USDC, switch to Arc Mainnet. Mainnet transactions involve real funds and cannot be reversed.'}
              </p>
              <SwitchNetworkButton
                target={NETWORK.isMainnet ? 'testnet' : 'mainnet'}
                className={`${NETWORK.isMainnet ? 'btn-primary' : 'btn-ghost'} mt-3 min-h-11`}
              >
                {NETWORK.isMainnet ? 'Switch to Arc Testnet' : 'Switch to Arc Mainnet'}
              </SwitchNetworkButton>
            </section>

          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
