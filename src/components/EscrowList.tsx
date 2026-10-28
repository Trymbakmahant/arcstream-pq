import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { Loader2, Inbox, TriangleAlert, Wallet } from 'lucide-react'
import { VAULT_ADDRESS } from '@/contracts/vault'
import type { EscrowView } from '@/hooks/useEscrows'
import { EscrowCard, type EscrowRole } from '@/components/EscrowCard'
import type { PqAuthRequest } from '@/components/PqAuthModal'

interface Props {
  title: string
  role: EscrowRole
  escrows: EscrowView[]
  isLoading: boolean
  isError: boolean
  emptyCopy: string
  onSubmitWork: (escrow: EscrowView, index: number) => void
  onViewDetails: (escrow: EscrowView, index: number) => void
  onPqAuth: (request: PqAuthRequest) => void
}

export function EscrowList({ title, role, escrows, isLoading, isError, emptyCopy, onSubmitWork, onViewDetails, onPqAuth }: Props) {
  const { isConnected } = useAccount()

  return (
    <section>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="display text-xl font-bold text-brandHighlight">{title}</h2>
        {escrows.length > 0 && (
          <span className="rounded-full bg-brandSecondary/50 px-3 py-1 text-xs font-bold tabular-nums text-brandHighlight">
            {escrows.length}
          </span>
        )}
      </div>

      {!VAULT_ADDRESS ? (
        <Notice icon={<TriangleAlert className="size-5" />} heading="Contract not deployed yet">
          Escrows will appear here once ArcStreamVault is deployed to Arc Testnet and connected to this app.
        </Notice>
      ) : !isConnected ? (
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
      ) : isLoading ? (
        <div className="space-y-3" aria-busy="true" aria-label="Loading escrows">
          {[0, 1].map((i) => (
            <div key={i} className="h-40 animate-pulse rounded-2xl bg-brandSecondary/25" />
          ))}
          <p className="flex items-center gap-2 text-sm text-brandHighlight/70">
            <Loader2 className="size-4 animate-spin" /> Reading escrows from Arc Testnet
          </p>
        </div>
      ) : isError ? (
        <Notice icon={<TriangleAlert className="size-5" />} heading="Could not load escrows">
          The network did not respond. It will retry automatically.
        </Notice>
      ) : escrows.length === 0 ? (
        <Notice icon={<Inbox className="size-5" />} heading="Nothing here yet">
          {emptyCopy}
        </Notice>
      ) : (
        <div className="space-y-4">
          {escrows.map((escrow) => (
            <EscrowCard key={escrow.id.toString()} escrow={escrow} role={role}
              onSubmitWork={onSubmitWork}
              onViewDetails={onViewDetails}
              onPqAuth={onPqAuth}
            />
          ))}
        </div>
      )}
    </section>
  )
}

function Notice({ icon, heading, children }: { icon: React.ReactNode; heading: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-dashed border-brandSecondary bg-brandSecondary/10 p-6 text-brandHighlight">
      <div className="flex items-center gap-2 font-semibold">
        {icon}
        {heading}
      </div>
      <div className="mt-2 text-sm text-brandHighlight/80">{children}</div>
    </div>
  )
}
