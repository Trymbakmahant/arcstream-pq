import { useMemo, useState } from 'react'
import { useAccount } from 'wagmi'
import { LayoutGrid, List, Plus } from 'lucide-react'
import { VAULT_ADDRESS } from '@/contracts/vault'
import type { EscrowView } from '@/hooks/useEscrows'
import { matchesQuery, matchesTab, type MilestoneRow, type RowRole, type TabId } from '@/lib/rows'
import { EscrowCard } from '@/components/EscrowCard'
import type { PqAuthRequest } from '@/components/PqAuthModal'
import { EscrowTable } from '@/components/dashboard/EscrowTable'
import {
  EmptyState,
  ErrorState,
  LoadingState,
  NotConnected,
  NotDeployed,
} from '@/components/dashboard/PanelStates'

const TABS: { id: TabId; label: string }[] = [
  { id: 'all', label: 'All Escrows' },
  { id: 'employer', label: 'Employer View' },
  { id: 'contractor', label: 'Contractor View' },
  { id: 'review', label: 'Needs Review' },
  { id: 'completed', label: 'Completed' },
]

interface Props {
  rows: MilestoneRow[]
  query: string
  loading: boolean
  error: boolean
  onCreate: () => void
  onSubmitWork: (escrow: EscrowView, index: number) => void
  onViewDetails: (role: RowRole) => (escrow: EscrowView, index: number) => void
  onPqAuth: (request: PqAuthRequest) => void
}

export function EscrowsPanel({ rows, query, loading, error, onCreate, onSubmitWork, onViewDetails, onPqAuth }: Props) {
  const { isConnected } = useAccount()
  const [tab, setTab] = useState<TabId>('all')
  const [view, setView] = useState<'list' | 'grid'>('list')

  const visible = useMemo(() => rows.filter((r) => matchesTab(r, tab) && matchesQuery(r, query)), [rows, tab, query])
  const counts = useMemo(
    () =>
      Object.fromEntries(TABS.map(({ id }) => [id, rows.filter((r) => matchesTab(r, id)).length])) as Record<
        TabId,
        number
      >,
    [rows],
  )

  const gridEscrows = useMemo(() => {
    const seen = new Map<string, { escrow: EscrowView; role: RowRole }>()
    for (const r of visible) {
      const id = r.escrow.id.toString()
      if (!seen.has(id)) seen.set(id, { escrow: r.escrow, role: r.role })
    }
    return [...seen.values()]
  }, [visible])

  return (
    <section aria-label="Escrows" className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div
          role="tablist"
          aria-label="Escrow filter"
          className="neu-sunken inline-flex max-w-full flex-wrap rounded-2xl border border-white/5 p-1 gap-1"
        >
          {TABS.map(({ id, label }) => {
            const active = tab === id
            return (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={active}
                onClick={() => setTab(id)}
                className={`inline-flex min-h-10 items-center gap-2 rounded-xl px-4 text-sm transition-all ${
                  active
                    ? 'neu-card border border-neonLime/40 font-semibold text-neonLime shadow-glow-lime'
                    : 'text-zinc-400 hover:bg-white/5 hover:text-white'
                }`}
              >
                {label}
                {isConnected && counts[id] > 0 && (
                  <span
                    className={`rounded-full px-1.5 py-0.5 text-[0.625rem] font-bold tabular-nums font-mono ${
                      active ? 'neu-sunken border border-neonLime/30 text-neonLime' : 'neu-sunken border border-white/5 text-zinc-500'
                    }`}
                  >
                    {counts[id]}
                  </span>
                )}
              </button>
            )
          })}
        </div>

        <div className="flex items-center gap-2">
          <div role="group" aria-label="View" className="neu-sunken inline-flex rounded-xl border border-white/5 p-1 gap-1">
            {(
              [
                { id: 'grid', label: 'Card view', icon: LayoutGrid },
                { id: 'list', label: 'Table view', icon: List },
              ] as const
            ).map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                aria-label={label}
                aria-pressed={view === id}
                onClick={() => setView(id)}
                className={`flex size-10 items-center justify-center rounded-lg transition-all ${
                  view === id ? 'neu-card border border-neonLime/40 text-neonLime shadow-glow-lime' : 'text-zinc-500 hover:text-white'
                }`}
              >
                <Icon className="size-4" />
              </button>
            ))}
          </div>
          <button type="button" className="btn-primary rounded-xl" onClick={onCreate}>
            <Plus className="size-4" />
            Add New Escrow
          </button>
        </div>
      </div>

      {!VAULT_ADDRESS ? (
        <NotDeployed />
      ) : !isConnected ? (
        <NotConnected />
      ) : error ? (
        <ErrorState />
      ) : loading ? (
        <div className="neu-card rounded-2xl border border-white/5">
          <LoadingState />
        </div>
      ) : visible.length === 0 ? (
        <EmptyState>
          {rows.length === 0
            ? 'Create an escrow, or ask an employer to name your wallet as contractor.'
            : 'No milestones match this filter or search.'}
        </EmptyState>
      ) : view === 'list' ? (
        <div className="neu-card overflow-hidden rounded-2xl border border-white/5">
          <EscrowTable rows={visible} onSubmitWork={onSubmitWork} onViewDetails={onViewDetails} onPqAuth={onPqAuth} />
        </div>
      ) : (
        <div className="grid gap-4 xl:grid-cols-2">
          {gridEscrows.map(({ escrow, role }) => (
            <EscrowCard
              key={escrow.id.toString()}
              escrow={escrow}
              role={role}
              onSubmitWork={onSubmitWork}
              onViewDetails={onViewDetails(role)}
              onPqAuth={onPqAuth}
            />
          ))}
        </div>
      )}
    </section>
  )
}
