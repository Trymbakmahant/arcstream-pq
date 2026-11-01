import type { ReactNode } from 'react'
import { ConnectKitButton } from 'connectkit'
import { Inbox, Loader2, TriangleAlert, Wallet } from 'lucide-react'
import { NETWORK } from '@/lib/network'

export function Notice({ icon, heading, children }: { icon: ReactNode; heading: string; children: ReactNode }) {
  return (
    <div className="neu-card rounded-2xl border border-white/5 p-8 text-white">
      <div className="flex items-center gap-2 font-semibold text-neonLime">
        {icon}
        <span className="text-white">{heading}</span>
      </div>
      <div className="mt-2 text-sm text-zinc-400">{children}</div>
    </div>
  )
}

export const NotDeployed = () => (
  <Notice icon={<TriangleAlert className="size-5 text-amber-400" />} heading="Contract not deployed yet">
    ArcStreamVault has not been deployed to {NETWORK.label} yet, so there is nothing to read. Escrows will appear here once it is deployed and connected to this app.
  </Notice>
)

export const ErrorState = () => (
  <Notice icon={<TriangleAlert className="size-5 text-neonPink" />} heading="Could not load escrows">
    The network did not respond. It will retry automatically.
  </Notice>
)

export const EmptyState = ({ children }: { children: ReactNode }) => (
  <Notice icon={<Inbox className="size-5 text-neonLime" />} heading="Nothing here yet">
    {children}
  </Notice>
)

export const LoadingState = () => (
  <div className="space-y-3 p-6" aria-busy="true" aria-label="Loading escrows">
    {[0, 1, 2].map((i) => (
      <div key={i} className="neu-sunken h-16 animate-pulse rounded-xl border border-white/5 bg-[#0b0b0b]" />
    ))}
    <p className="flex items-center gap-2 text-sm text-zinc-400">
      <Loader2 className="size-4 animate-spin text-neonLime" /> Reading escrows from {NETWORK.label}
    </p>
  </div>
)

export const NotConnected = () => (
  <div className="neu-card flex flex-col items-center justify-center rounded-2xl border border-white/5 p-10 text-center">
    <span className="neu-sunken flex size-14 items-center justify-center rounded-2xl border border-neonLime/30 text-neonLime shadow-glow-lime">
      <Wallet className="size-6" />
    </span>
    <h3 className="display mt-4 text-lg font-bold text-white">Wallet Not Connected</h3>
    <p className="mt-2 max-w-sm text-pretty text-sm text-zinc-400">
      Connect your wallet on {NETWORK.label} to view escrows you&apos;ve funded or work assigned to you.
    </p>
    <ConnectKitButton.Custom>
      {({ show }) => (
        <button
          type="button"
          onClick={show}
          className="btn-primary mt-5 rounded-xl px-6 py-2.5 text-sm font-semibold"
        >
          Connect Wallet
        </button>
      )}
    </ConnectKitButton.Custom>
  </div>
)
