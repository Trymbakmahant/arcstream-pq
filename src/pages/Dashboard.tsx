import { useState } from 'react'
import { Briefcase, HardHat } from 'lucide-react'
import { Header } from '@/components/Header'
import { NetworkBanner } from '@/components/NetworkBanner'
import { TxProvider } from '@/components/TxProvider'
import { CreateEscrowCard } from '@/components/CreateEscrowCard'
import { EscrowList } from '@/components/EscrowList'
import { SubmitWorkModal } from '@/components/SubmitWorkModal'
import { TaskDetailsDrawer, type DetailsTarget } from '@/components/TaskDetailsDrawer'
import { PqAuthModal, type PqAuthRequest } from '@/components/PqAuthModal'
import { useEscrows, type EscrowView } from '@/hooks/useEscrows'
import { useVaultActions } from '@/hooks/useVaultActions'
import { useDocumentTitle } from '@/lib/router'

type Tab = 'employer' | 'contractor'

const TABS: { id: Tab; label: string; icon: typeof Briefcase }[] = [
  { id: 'employer', label: 'Employer View (Fund & Approve)', icon: Briefcase },
  { id: 'contractor', label: 'Contractor View (Work & Claim)', icon: HardHat },
]

function Workspace() {
  const [tab, setTab] = useState<Tab>('employer')
  const [submitTarget, setSubmitTarget] = useState<{ escrow: EscrowView; index: number } | null>(null)
  const [details, setDetails] = useState<DetailsTarget | null>(null)
  const [pqRequest, setPqRequest] = useState<PqAuthRequest | null>(null)
  const { asEmployer, asContractor, isLoading, isError } = useEscrows()
  const actions = useVaultActions()

  const onSubmitWork = (escrow: EscrowView, index: number) => setSubmitTarget({ escrow, index })
  const onViewDetails = (role: DetailsTarget['role']) => (escrow: EscrowView, index: number) =>
    setDetails({ escrowId: escrow.id, index, role })
  const detailsEscrow = details
    ? (details.role === 'employer' ? asEmployer : asContractor).find((e) => e.id === details.escrowId)
    : undefined

  return (
    <main className="mx-auto max-w-6xl px-4 pb-24 pt-8 sm:px-6">
      <div className="mb-8 max-w-2xl">
        <h2 className="display text-balance text-3xl font-bold text-brandHighlight sm:text-4xl">
          Pay for finished work, milestone by milestone.
        </h2>
        <p className="mt-2 text-pretty text-brandHighlight/80">
          Lock USDC in escrow, let the contractor submit proof, approve what you accept, and the payout is released
          directly to them.
        </p>
      </div>

      <div className="mb-8 flex justify-center">
      <div
        role="tablist"
        aria-label="Workspace"
        className="inline-flex max-w-full flex-wrap justify-center rounded-xl border border-brandHighlight/10 bg-brandSecondary/30 p-1"
      >
        {TABS.map(({ id, label, icon: Icon }) => {
          const active = tab === id
          return (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => setTab(id)}
              className={`flex min-h-11 items-center justify-center gap-2 rounded-lg px-5 py-2 text-sm transition-all ${
                active
                  ? 'bg-brandHighlight font-medium text-brandMain shadow-sm'
                  : 'text-brandHighlight/70 hover:text-brandHighlight'
              }`}
            >
              <Icon className="size-4" />
              {label}
            </button>
          )
        })}
      </div>
      </div>

      {tab === 'employer' ? (
        <div className="grid gap-8 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]">
          <CreateEscrowCard />
          <EscrowList
            title="Active Escrows"
            role="employer"
            escrows={asEmployer}
            isLoading={isLoading}
            isError={isError}
            emptyCopy="Escrows you create will show up here with their milestones and any submitted work."
            onSubmitWork={onSubmitWork}
            onViewDetails={onViewDetails('employer')}
            onPqAuth={setPqRequest}
          />
        </div>
      ) : (
        <div className="mx-auto max-w-3xl">
          <EscrowList
            title="Your Contracts"
            role="contractor"
            escrows={asContractor}
            isLoading={isLoading}
            isError={isError}
            emptyCopy="When an employer names your wallet as contractor, the escrow appears here."
            onSubmitWork={onSubmitWork}
            onViewDetails={onViewDetails('contractor')}
            onPqAuth={setPqRequest}
          />
        </div>
      )}

      <TaskDetailsDrawer
        target={details}
        escrow={detailsEscrow}
        onClose={() => setDetails(null)}
        onSubmitWork={onSubmitWork}
        onPqAuth={setPqRequest}
      />

      <PqAuthModal request={pqRequest} onClose={() => setPqRequest(null)} />

      <SubmitWorkModal
        target={submitTarget}
        onClose={() => setSubmitTarget(null)}
        onSubmit={(escrow, index, proof) => {
          setSubmitTarget(null)
          void actions.submitWork(escrow.id, index, proof)
        }}
      />
    </main>
  )
}

export default function Dashboard() {
  useDocumentTitle('Dashboard | ArcStream-PQ')
  return (
    <TxProvider>
      <div className="min-h-dvh bg-brandMain">
        <Header />
        <NetworkBanner />
        <Workspace />
      </div>
    </TxProvider>
  )
}
