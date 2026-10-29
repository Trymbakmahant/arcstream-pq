import { useEffect, useRef } from 'react'
import { useAccount, useSwitchChain } from 'wagmi'
import { Loader2, Network } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { NETWORK } from '@/lib/network'

/**
 * Prompts the wallet to switch to the selected Arc network as soon as it connects on another chain,
 * and keeps a visible switch button for when the prompt is dismissed.
 */
export function NetworkBanner() {
  const { isConnected, chainId, address } = useAccount()
  const { switchChain, isPending } = useSwitchChain()
  const prompted = useRef<string | null>(null)
  const wrongChain = isConnected && chainId !== ARC_CHAIN_ID

  useEffect(() => {
    if (wrongChain && address && prompted.current !== address) {
      prompted.current = address
      switchChain({ chainId: ARC_CHAIN_ID })
    }
    if (!isConnected) prompted.current = null
  }, [wrongChain, address, isConnected, switchChain])

  if (!wrongChain) return null

  return (
    <div className="border-b border-brandSecondary bg-brandSecondary/40">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <p className="flex items-center gap-2 text-sm font-semibold text-brandHighlight">
          <Network className="size-4" />
          Your wallet is on another network. Switch to {NETWORK.label} to continue.
        </p>
        <button
          type="button"
          className="btn-primary"
          disabled={isPending}
          onClick={() => switchChain({ chainId: ARC_CHAIN_ID })}
        >
          {isPending && <Loader2 className="size-4 animate-spin" />}
          Switch to {NETWORK.label}
        </button>
      </div>
    </div>
  )
}
