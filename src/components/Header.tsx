import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { ArrowLeft, Droplets, Fingerprint, Landmark, Loader2, Wallet } from 'lucide-react'
import { Link } from '@/lib/router'
import { TokenUSDC } from '@web3icons/react'
import { ARC_CHAIN_ID } from '@/config'
import { FAUCET_URL } from '@/contracts/vault'
import { useUsdcBalance } from '@/hooks/useUsdc'
import { usePasskey } from '@/hooks/usePasskey'
import { fingerprint as shortHash } from '@/lib/pq'
import { fmtUsdc, shortAddress } from '@/lib/money'

export function Header() {
  const { isConnected, chainId } = useAccount()
  const { data: balance, isLoading } = useUsdcBalance()
  const onArc = chainId === ARC_CHAIN_ID
  const passkey = usePasskey()

  return (
    <header className="bg-brandHighlight text-brandMain">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-3 px-4 py-4 sm:px-6">
        <div className="flex items-center gap-3">
          <Link
            to="/"
            className="inline-flex min-h-11 items-center gap-1.5 rounded-full border border-brandMain/25 px-3 text-xs font-semibold text-brandMain hover:bg-brandMain/10"
          >
            <ArrowLeft className="size-4" />
            Back to Home
          </Link>
          <span className="flex size-10 items-center justify-center rounded-xl bg-brandSecondary text-brandHighlight">
            <Landmark className="size-5" />
          </span>
          <div>
            <h1 className="display text-lg font-bold leading-none">ArcStream-PQ</h1>
            <p className="mt-1 text-xs text-brandMain/70">USDC milestone escrow</p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2 sm:gap-3">
          <span
            className="inline-flex min-h-9 items-center gap-2 rounded-full border border-brandMain/25 px-3 text-xs font-semibold"
            title="Network"
          >
            <span className="relative flex size-2.5">
              {(!isConnected || onArc) && (
                <span className="absolute inline-flex size-full animate-ping rounded-full bg-brandSecondary opacity-70" />
              )}
              <span
                className={`relative inline-flex size-2.5 rounded-full ${
                  !isConnected || onArc ? 'bg-brandSecondary' : 'border border-brandMain bg-transparent'
                }`}
              />
            </span>
            {isConnected && !onArc ? 'Wrong network' : `Arc Testnet (${ARC_CHAIN_ID})`}
          </span>

          <span
            className={`inline-flex min-h-9 items-center gap-2 rounded-full border px-3 text-xs font-semibold ${
              passkey.registered
                ? 'border-brandSecondary bg-brandSecondary/15 shadow-[0_0_16px_rgba(169,187,135,0.45)]'
                : 'border-brandMain/25'
            }`}
            title="Touch ID / Face ID unlocks hash-based one-time secrets that the contract checks before an employer can release or refund a protected escrow. The wallet key itself is still a standard key."
          >
            <Fingerprint className={`size-4 ${passkey.registered ? 'text-brandSecondary' : ''}`} />
            Biometric PQ Shield
            <span className="text-brandMain/70">
              {passkey.registered && passkey.fingerprint ? `Key ${shortHash(passkey.fingerprint)}` : 'not set up'}
            </span>
          </span>

          {isConnected && !passkey.registered && (
            <button
              type="button"
              disabled={passkey.busy || !passkey.supported}
              onClick={() => {
                void passkey.register()
              }}
              className="inline-flex min-h-11 items-center gap-2 rounded-full border border-brandSecondary px-4 text-sm font-semibold text-brandMain hover:bg-brandSecondary/20 disabled:opacity-50"
            >
              {passkey.busy ? <Loader2 className="size-4 animate-spin" /> : <Fingerprint className="size-4" />}
              Set Up Touch ID / Face ID Key
            </button>
          )}

          {isConnected && (
            <span className="inline-flex min-h-9 items-center gap-2 rounded-full border border-brandMain/25 px-3 text-xs font-semibold tabular-nums">
              <TokenUSDC variant="branded" size={16} />
              {isLoading || balance === undefined ? '...' : `${fmtUsdc(balance)} USDC`}
            </span>
          )}

          <a
            href={FAUCET_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex min-h-11 items-center gap-2 rounded-full border border-brandSecondary px-4 text-sm font-semibold text-brandMain hover:bg-brandSecondary/20"
          >
            <Droplets className="size-4" />
            Get Free Testnet USDC
          </a>

          <ConnectKitButton.Custom>
            {({ isConnected: connected, show, address }) => (
              <button
                type="button"
                onClick={show}
                className="inline-flex min-h-11 items-center gap-2 rounded-full bg-brandMain px-5 text-sm font-semibold text-brandHighlight transition-colors hover:bg-white"
              >
                <Wallet className="size-4" />
                {connected && address ? shortAddress(address) : 'Connect Wallet'}
              </button>
            )}
          </ConnectKitButton.Custom>
        </div>
      </div>
    </header>
  )
}
