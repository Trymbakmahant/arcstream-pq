import { useMemo } from 'react'
import { BadgeCheck, Download, FileText, Landmark } from 'lucide-react'
import { VAULT_ADDRESS } from '@/contracts/vault'
import { NETWORK } from '@/lib/network'
import type { EscrowView } from '@/hooks/useEscrows'
import { fmtUsdc } from '@/lib/money'
import { buildCsv, summarize, type MilestoneRow } from '@/lib/rows'

interface Props {
  escrows: EscrowView[]
  rows: MilestoneRow[]
  address: string | undefined
  loading: boolean
}

export function StatCards({ escrows, rows, address, loading }: Props) {
  const stats = useMemo(() => summarize(escrows, address), [escrows, address])

  const download = () => {
    if (!VAULT_ADDRESS) return
    const csv = buildCsv(rows, VAULT_ADDRESS, `${NETWORK.label} (${NETWORK.chainId})`)
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
    const link = document.createElement('a')
    link.href = url
    link.download = `arcstream-escrow-report-${new Date().toISOString().slice(0, 10)}.csv`
    link.click()
    URL.revokeObjectURL(url)
  }

  const money = (value: bigint) => (loading || !address ? '--' : `$${fmtUsdc(value)}`)

  return (
    <section className="grid gap-4 xl:grid-cols-3" aria-label="Summary">
      <div className="neu-card flex flex-col rounded-2xl p-6">
        <span className="flex size-11 items-center justify-center rounded-xl bg-[#0b0b0b] border border-neonPink/30 text-neonPink shadow-glow-pink">
          <FileText className="size-5" />
        </span>
        <h3 className="display mt-5 text-lg font-bold text-white">Generate Escrow Report</h3>
        <p className="mt-1 text-sm text-pretty text-zinc-400">
          Export a snapshot of your escrows read from the contract: amounts, statuses, work proofs and PQ commitments.
        </p>
        <button
          type="button"
          className="btn-pink mt-5 w-fit rounded-xl"
          disabled={rows.length === 0}
          onClick={download}
        >
          <Download className="size-4" />
          Download Report (CSV)
        </button>
      </div>

      <div className="neu-card rounded-2xl p-6">
        <span className="flex size-11 items-center justify-center rounded-xl bg-[#0b0b0b] border border-neonLime/30 text-neonLime shadow-glow-lime">
          <Landmark className="size-5" />
        </span>
        <p className="label-caps mt-5 text-zinc-400">Value locked in your escrows</p>
        <p className="mt-2 font-mono text-4xl font-semibold tabular-nums tracking-tight text-white">
          {money(stats.locked)}
        </p>
        <p className="neu-sunken mt-5 inline-flex rounded-lg border border-white/5 px-2.5 py-1 text-xs font-medium text-neonLime font-mono">
          {address ? `${stats.activeEscrows} active as employer` : 'Connect a wallet to see your totals'}
        </p>
      </div>

      <div className="neu-card rounded-2xl p-6">
        <span className="flex size-11 items-center justify-center rounded-xl bg-[#0b0b0b] border border-white/10 text-zinc-300">
          <BadgeCheck className="size-5" />
        </span>
        <p className="label-caps mt-5 text-zinc-400">Disbursed escrow payouts</p>
        <p className="mt-2 font-mono text-4xl font-semibold tabular-nums tracking-tight text-white">
          {money(stats.paidOut)}
        </p>
        <p className="neu-sunken mt-5 inline-flex rounded-lg border border-white/5 px-2.5 py-1 text-xs font-medium tabular-nums text-zinc-300 font-mono">
          {address ? `Received as contractor $${fmtUsdc(stats.received)}` : 'Paid out as employer'}
        </p>
      </div>
    </section>
  )
}
