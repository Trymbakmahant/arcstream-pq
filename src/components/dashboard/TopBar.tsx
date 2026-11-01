import { forwardRef } from 'react'
import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { TokenUSDC } from '@web3icons/react'
import { ChevronDown, Droplets, Fingerprint, Menu, Search, Wallet } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { NetworkSwitcher } from '@/components/NetworkSwitcher'
import { NETWORK } from '@/lib/network'
import { usePasskey } from '@/hooks/usePasskey'
import { useUsdcBalance } from '@/hooks/useUsdc'
import { fmtUsdc, shortAddress } from '@/lib/money'

interface Props {
  query: string
  onQuery: (value: string) => void
  onMenu: () => void
  onFund: () => void
}

export const TopBar = forwardRef<HTMLInputElement, Props>(function TopBar({ query, onQuery, onMenu, onFund }, searchRef) {
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
          className="neu-card flex size-11 shrink-0 items-center justify-center rounded-xl border border-white/5 text-zinc-300 hover:text-white lg:hidden"
          aria-label="Open menu"
        >
          <Menu className="size-5" />
        </button>
        <label className="relative block w-full max-w-xl">
          <span className="sr-only">Search escrows</span>
          <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-zinc-500" />
          <input
            ref={searchRef}
            value={query}
            onChange={(e) => onQuery(e.target.value)}
            placeholder="Search escrow, counterparty, or milestone..."
            className="neu-sunken min-h-12 w-full rounded-2xl border border-white/5 pl-11 pr-20 text-sm text-white outline-none placeholder:text-zinc-500 focus:border-neonLime focus:shadow-glow-lime transition-all"
          />
          <kbd className="pointer-events-none absolute right-3 top-1/2 hidden -translate-y-1/2 rounded-lg border border-white/5 bg-white/5 px-2.5 py-1 font-mono text-[0.625rem] text-zinc-400 sm:block">
            Ctrl K
          </kbd>
        </label>
      </div>

      <div className="flex flex-wrap items-center gap-2 sm:gap-3">
        <NetworkSwitcher wrongNetwork={isConnected && !onArc} />

        <button
          type="button"
          onClick={onFund}
          className="neu-card inline-flex min-h-10 items-center gap-2 rounded-xl border border-neonPink/40 px-4 text-xs font-semibold text-neonPink hover:shadow-glow-pink transition-all"
        >
          <Droplets className="size-4" />
          {NETWORK.isMainnet ? 'Fund with USDC' : 'Get Free Testnet USDC'}
        </button>

        <button
          type="button"
          disabled={passkey.registered || !isConnected || passkey.busy || !passkey.supported}
          onClick={() => {
            void passkey.register()
          }}
          className={`neu-card inline-flex min-h-10 items-center gap-2 rounded-xl px-4 text-xs font-semibold transition-all ${
            passkey.registered
              ? 'border border-neonLime/50 text-neonLime shadow-glow-lime font-bold'
              : 'border border-white/5 text-zinc-400 hover:text-white'
          }`}
          title={
            passkey.registered
              ? 'Touch ID / Face ID unlocks a post-quantum (SLH-DSA) signing key for employer release and refund on protected escrows.'
              : 'Set up Touch ID / Face ID to protect your escrows.'
          }
        >
          <Fingerprint className="size-4 text-neonPink" />
          PQ Shield: <span className="font-mono">{passkey.registered ? 'ACTIVE' : 'SET UP'}</span>
        </button>

        <ConnectKitButton.Custom>
          {({ show }) => (
            <button
              type="button"
              onClick={show}
              className="neu-card ml-auto inline-flex min-h-12 items-center gap-3 rounded-2xl border border-white/5 py-1.5 pl-2 pr-4 text-left hover:border-white/10 transition-all"
            >
              {isConnected && address ? (
                <>
                  <span className="flex size-9 items-center justify-center rounded-xl bg-neonLime/20 border border-neonLime/30 text-xs font-bold font-mono text-neonLime">
                    {address.slice(2, 4).toUpperCase()}
                  </span>
                  <span className="min-w-0">
                    <span className="block font-mono text-sm font-semibold leading-tight text-white">
                      {shortAddress(address)}
                    </span>
                    <span className="flex items-center gap-1.5 font-mono text-[0.6875rem] tabular-nums leading-tight text-zinc-400">
                      <TokenUSDC variant="branded" size={12} />
                      {balance === undefined ? '...' : `${fmtUsdc(balance)} USDC`}
                    </span>
                  </span>
                  <ChevronDown className="size-4 text-zinc-400" />
                </>
              ) : (
                <>
                  <span className="flex size-9 items-center justify-center rounded-xl bg-white/5 border border-white/5 text-neonLime">
                    <Wallet className="size-4" />
                  </span>
                  <span className="text-sm font-semibold text-white">Connect Wallet</span>
                </>
              )}
            </button>
          )}
        </ConnectKitButton.Custom>
      </div>
    </div>
  )
})
