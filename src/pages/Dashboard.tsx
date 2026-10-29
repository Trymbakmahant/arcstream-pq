import { useEffect, useMemo, useRef, useState } from 'react'
import { useAccount } from 'wagmi'
import { NetworkBanner } from '@/components/NetworkBanner'
import { PqAuthModal, type PqAuthRequest } from '@/components/PqAuthModal'
import { SubmitWorkModal } from '@/components/SubmitWorkModal'
import { TaskDetailsDrawer, type DetailsTarget } from '@/components/TaskDetailsDrawer'
import { TxProvider } from '@/components/TxProvider'
import { CreateEscrowModal } from '@/components/dashboard/CreateEscrowModal'
import { EscrowsPanel } from '@/components/dashboard/EscrowsPanel'
import { Sidebar } from '@/components/dashboard/Sidebar'
import { StatCards } from '@/components/dashboard/StatCards'
import { TopBar } from '@/components/dashboard/TopBar'
import { useEscrows, type EscrowView } from '@/hooks/useEscrows'
import { useVaultActions } from '@/hooks/useVaultActions'
import { buildRows, type RowRole } from '@/lib/rows'
import { useDocumentTitle } from '@/lib/router'

function DashboardContent() {
  const { address } = useAccount()
  const { data, asEmployer, asContractor, isLoading, isError } = useEscrows()
  const actions = useVaultActions()

  const [menuOpen, setMenuOpen] = useState(false)
  const [createOpen, setCreateOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [submitTarget, setSubmitTarget] = useState<{ escrow: EscrowView; index: number } | null>(null)
  const [details, setDetails] = useState<DetailsTarget | null>(null)
  const [pqRequest, setPqRequest] = useState<PqAuthRequest | null>(null)
  const searchRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        searchRef.current?.focus()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const escrows = useMemo(() => data ?? [], [data])
  const rows = useMemo(() => buildRows(escrows, address), [escrows, address])
  const mine = useMemo(() => [...asEmployer, ...asContractor], [asEmployer, asContractor])

  const detailsEscrow = details ? escrows.find((e) => e.id === details.escrowId) : undefined

  const onSubmitWork = (escrow: EscrowView, index: number) => setSubmitTarget({ escrow, index })
  const onViewDetails = (role: RowRole) => (escrow: EscrowView, index: number) =>
    setDetails({ escrowId: escrow.id, index, role })

  return (
    <div className="min-h-dvh bg-brandMain">
      <Sidebar open={menuOpen} onClose={() => setMenuOpen(false)} onCreate={() => setCreateOpen(true)} />

      <div className="lg:pl-64">
        <NetworkBanner />
        <main className="mx-auto max-w-7xl space-y-6 px-4 py-6 sm:px-6 lg:px-8">
          <TopBar ref={searchRef} query={query} onQuery={setQuery} onMenu={() => setMenuOpen(true)} />
          <StatCards escrows={mine} rows={rows} address={address} loading={isLoading} />
          <EscrowsPanel
            rows={rows}
            query={query}
            loading={isLoading}
            error={isError}
            onCreate={() => setCreateOpen(true)}
            onSubmitWork={onSubmitWork}
            onViewDetails={onViewDetails}
            onPqAuth={setPqRequest}
          />
        </main>
      </div>

      <CreateEscrowModal open={createOpen} onClose={() => setCreateOpen(false)} />

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
    </div>
  )
}

export default function Dashboard() {
  useDocumentTitle('Dashboard | ArcStream-PQ')
  return (
    <TxProvider>
      <DashboardContent />
    </TxProvider>
  )
}
