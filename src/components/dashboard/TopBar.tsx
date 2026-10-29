import { forwardRef } from 'react'
import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { TokenUSDC } from '@web3icons/react'
import { ChevronDown, Droplets, Fingerprint, Menu, Search, Wallet } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { FAUCET_URL } from '@/contracts/vault'
import { usePasskey } from '@/hooks/usePasskey'
import { useUsdcBalance } from '@/hooks/useUsdc'
import { fmtUsdc, shortAddress } from '@/lib/money'

interface Props {
  query: string
  onQuery: (value: string) => void
  onMenu: () => void
}

export const TopBar = forwardRef<HTMLInputElement, Props>(function TopBar({ query, onQuery, onMenu }, searchRef) {
  const { isConnected, chainId, address } = useAccount()
  const { data: balance } = useUsdcBalance()
  const passkey = usePasskey()
  const onArc = chainId === ARC_CHAIN_ID

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onMenu}
          className="flex size-11 shrink-0 items-center justify-center rounded-full border border-brandHighlight/10 bg-white text-brandHighlight lg:hidden"
          aria-label="Open menu"
        >
          <Menu className="size-5" />
        </button>
        <label className="relative block w-full max-w-xl">
          <span className="sr-only">Search escrows</span>
          <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-brandHighlight/50" />
          <input
            ref={searchRef}
            value={query}
            onChange={(e) => onQuery(e.target.value)}
            placeholder="Search escrow, counterparty, or milestone..."
            className="min-h-12 w-full rounded-full border border-brandHighlight/10 bg-white pl-11 pr-20 text-sm text-brandHighlight outline-none placeholder:text-brandHighlight/45 focus:border-brandSecondary focus:ring-[3px] focus:ring-brandSecondary/55"
          />
          <kbd className="pointer-events-none absolute right-3 top-1/2 hidden -translate-y-1/2 rounded-full bg-brandSecondary/30 px-2.5 py-1 font-mono text-[0.625rem] text-brandHighlight/70 sm:block">
            Ctrl K
          </kbd>
        </label>
      </div>

      <div className="flex flex-wrap items-center gap-2 sm:gap-3">
        <span className="inline-flex min-h-10 items-center gap-2 rounded-full border border-brandHighlight/10 bg-white px-4 font-mono text-xs font-medium text-brandHighlight">
          <span className={`size-2 rounded-full ${!isConnected || onArc ? 'bg-brandSecondary' : 'border border-brandHighlight'}`} />
          {isConnected && !onArc ? 'Wrong network' : `Arc Testnet (${ARC_CHAIN_ID})`}
        </span>

        <a
          href={FAUCET_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex min-h-10 items-center gap-2 rounded-full border border-brandSecondary bg-brandSecondary/40 px-4 text-xs font-semibold text-brandHighlight hover:bg-brandSecondary/60"
        >
          <Droplets className="size-4" />
          Get Free Testnet USDC
        </a>

        <button
          type="button"
          disabled={passkey.registered || !isConnected || passkey.busy || !passkey.supported}
          onClick={() => {
            void passkey.register()
          }}
          className={`inline-flex min-h-10 items-center gap-2 rounded-full px-4 text-xs font-semibold ${
            passkey.registered
              ? 'bg-brandHighlight text-brandMain shadow-[0_0_14px_rgba(169,187,135,0.5)]'
              : 'border border-brandHighlight/40 bg-white text-brandHighlight'
          }`}
          title={
            passkey.registered
              ? 'Touch ID / Face ID unlocks a post-quantum (SLH-DSA) signing key for employer release and refund on protected escrows.'
              : 'Set up Touch ID / Face ID to protect your escrows.'
          }
        >
          <Fingerprint className="size-4" />
          PQ Shield: <span className="font-mono">{passkey.registered ? 'ACTIVE' : 'SET UP'}</span>
        </button>

        <ConnectKitButton.Custom>
          {({ show }) => (
            <button
              type="button"
              onClick={show}
              className="ml-auto inline-flex min-h-12 items-center gap-3 rounded-full border border-brandHighlight/10 bg-white py-1.5 pl-1.5 pr-4 text-left"
            >
              {isConnected && address ? (
                <>
                  <span className="flex size-9 items-center justify-center rounded-full bg-brandHighlight text-xs font-bold text-brandMain">
                    {address.slice(2, 4).toUpperCase()}
                  </span>
                  <span className="min-w-0">
                    <span className="block font-mono text-sm font-semibold leading-tight text-brandHighlight">
                      {shortAddress(address)}
                    </span>
                    <span className="flex items-center gap-1 font-mono text-[0.6875rem] tabular-nums leading-tight text-brandHighlight/70">
                      <TokenUSDC variant="branded" size={12} />
                      {balance === undefined ? '...' : `${fmtUsdc(balance)} USDC`}
                    </span>
                  </span>
                  <ChevronDown className="size-4 text-brandHighlight/60" />
                </>
              ) : (
                <>
                  <span className="flex size-9 items-center justify-center rounded-full bg-brandSecondary text-brandHighlight">
                    <Wallet className="size-4" />
                  </span>
                  <span className="text-sm font-semibold text-brandHighlight">Connect Wallet</span>
                </>
              )}
            </button>
          )}
        </ConnectKitButton.Custom>
      </div>
    </div>
  )
})
