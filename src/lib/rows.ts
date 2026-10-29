import { milestoneStatus, type EscrowView, type MilestoneStatus, type MilestoneView } from '@/hooks/useEscrows'
import { milestoneTitle } from '@/lib/text'
import { formatUnits } from 'viem'

export type RowRole = 'employer' | 'contractor'

export interface MilestoneRow {
  key: string
  escrow: EscrowView
  index: number
  role: RowRole
  milestone: MilestoneView
  status: MilestoneStatus
  counterparty: string
  /** True when the connected wallet has a next step to take on this milestone. */
  needsAction: boolean
}

export type TabId = 'all' | 'employer' | 'contractor' | 'review' | 'completed'

export function buildRows(escrows: EscrowView[], address: string | undefined): MilestoneRow[] {
  if (!address) return []
  const me = address.toLowerCase()
  const rows: MilestoneRow[] = []
  for (const escrow of escrows) {
    const role: RowRole | null =
      escrow.employer.toLowerCase() === me ? 'employer' : escrow.contractor.toLowerCase() === me ? 'contractor' : null
    if (!role) continue
    escrow.milestones.forEach((milestone, index) => {
      const status = milestoneStatus(escrow, milestone)
      const needsAction =
        role === 'employer'
          ? status === 'WORK SUBMITTED' || status === 'APPROVED'
          : status === 'PENDING' || status === 'APPROVED'
      rows.push({
        key: `${escrow.id}-${index}`,
        escrow,
        index,
        role,
        milestone,
        status,
        counterparty: role === 'employer' ? escrow.contractor : escrow.employer,
        needsAction,
      })
    })
  }
  return rows
}

export function matchesTab(row: MilestoneRow, tab: TabId): boolean {
  switch (tab) {
    case 'all':
      return true
    case 'employer':
    case 'contractor':
      return row.role === tab
    case 'review':
      return row.role === 'employer' && row.status === 'WORK SUBMITTED'
    case 'completed':
      return row.status === 'RELEASED'
  }
}

export function matchesQuery(row: MilestoneRow, query: string): boolean {
  const q = query.trim().toLowerCase()
  if (!q) return true
  return [
    row.counterparty,
    row.escrow.id.toString(),
    `esc-${row.escrow.id}`,
    `${row.escrow.id}-m${row.index + 1}`,
    row.milestone.description,
    row.status,
  ].some((field) => field.toLowerCase().includes(q))
}

export function summarize(escrows: EscrowView[], address: string | undefined) {
  const me = address?.toLowerCase()
  let locked = 0n
  let paidOut = 0n
  let received = 0n
  let activeEscrows = 0
  for (const e of escrows) {
    if (e.employer.toLowerCase() === me) {
      const remaining = e.totalDeposited - e.totalReleased - e.refunded
      locked += remaining
      paidOut += e.totalReleased
      if (remaining > 0n) activeEscrows += 1
    } else if (e.contractor.toLowerCase() === me) {
      received += e.totalReleased
    }
  }
  return { locked, paidOut, received, activeEscrows }
}

const csvCell = (value: string) => `"${value.replace(/"/g, '""')}"`

export function buildCsv(rows: MilestoneRow[], contract: string, chain: string): string {
  const header = [
    'escrow_id',
    'milestone',
    'your_role',
    'counterparty',
    'amount_usdc',
    'status',
    'title',
    'work_proof',
    'pq_protected',
    'pq_commitment',
    'contract',
    'chain',
  ]
  const lines = rows.map((r) =>
    [
      r.escrow.id.toString(),
      String(r.index + 1),
      r.role,
      r.counterparty,
      formatUnits(r.milestone.amount, 6),
      r.status,
      milestoneTitle(r.milestone.description),
      r.milestone.workProofHash,
      String(r.escrow.isPQProtected),
      r.escrow.isPQProtected ? r.escrow.pqCommitment : '',
      contract,
      chain,
    ]
      .map(csvCell)
      .join(','),
  )
  return [header.join(','), ...lines].join('\n')
}
