import type { ReactNode } from 'react'
import { ConnectKitButton } from 'connectkit'
import { Inbox, Loader2, TriangleAlert, Wallet } from 'lucide-react'

export function Notice({ icon, heading, children }: { icon: ReactNode; heading: string; children: ReactNode }) {
  return (
    <div className="rounded-2xl border border-dashed border-brandSecondary bg-brandSecondary/10 p-8 text-brandHighlight">
      <div className="flex items-center gap-2 font-semibold">
        {icon}
        {heading}
      </div>
      <div className="mt-2 text-sm text-brandHighlight/80">{children}</div>
    </div>
  )
}

export const NotDeployed = () => (
  <Notice icon={<TriangleAlert className="size-5" />} heading="Contract not deployed yet">
    Escrows will appear here once ArcStreamVault is deployed to Arc Testnet and connected to this app.
  </Notice>
)

export const ErrorState = () => (
  <Notice icon={<TriangleAlert className="size-5" />} heading="Could not load escrows">
    The network did not respond. It will retry automatically.
  </Notice>
)

export const EmptyState = ({ children }: { children: ReactNode }) => (
  <Notice icon={<Inbox className="size-5" />} heading="Nothing here yet">
    {children}
  </Notice>
)

export const LoadingState = () => (
  <div className="space-y-3 p-6" aria-busy="true" aria-label="Loading escrows">
    {[0, 1, 2].map((i) => (
      <div key={i} className="h-16 animate-pulse rounded-xl bg-brandSecondary/25" />
    ))}
    <p className="flex items-center gap-2 text-sm text-brandHighlight/70">
      <Loader2 className="size-4 animate-spin" /> Reading escrows from Arc Testnet
    </p>
  </div>
)

export const NotConnected = () => (
  <div className="flex flex-col items-center justify-center rounded-2xl border border-brandHighlight/15 bg-brandSecondary/20 p-10 text-center">
    <span className="flex size-14 items-center justify-center rounded-full bg-brandSecondary/50 text-brandHighlight">
      <Wallet className="size-6" />
    </span>
    <h3 className="display mt-4 text-lg font-bold text-brandHighlight">Wallet Not Connected</h3>
    <p className="mt-2 max-w-sm text-pretty text-sm text-brandHighlight/80">
      Connect your wallet on Arc Testnet to view escrows you&apos;ve funded or work assigned to you.
    </p>
    <ConnectKitButton.Custom>
      {({ show }) => (
        <button
          type="button"
          onClick={show}
          className="mt-4 min-h-11 rounded-xl bg-brandHighlight px-6 py-2.5 text-sm font-semibold text-brandMain transition-opacity hover:opacity-90"
        >
          Connect Wallet
        </button>
      )}
    </ConnectKitButton.Custom>
  </div>
)
