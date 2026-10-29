import { useState, type ReactNode } from 'react'
import { ExternalLink } from 'lucide-react'
import { CopyButton, ProofViewer } from '@/components/ui'
import { VAULT_ADDRESS, txUrl } from '@/contracts/vault'
import type { EscrowView } from '@/hooks/useEscrows'
import type { SettlementRecord } from '@/hooks/useSettlement'
import { fmtUsdc } from '@/lib/money'
import { NETWORK } from '@/lib/network'
import { fingerprint } from '@/lib/pq'
import { milestoneTitle } from '@/lib/text'

const PQ_PRECOMPILE = '0x1800000000000000000000000000000000000004'

const when = (seconds: number | null) =>
  seconds === null ? 'Unavailable' : new Date(seconds * 1000).toLocaleString(undefined, { dateStyle: 'long', timeStyle: 'short' })

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-[0.6875rem] font-bold uppercase tracking-[0.1em] text-brandHighlight/60">{label}</dt>
      <dd className="mt-1 break-all text-sm text-brandHighlight">{children}</dd>
    </div>
  )
}

function Party({ role, address }: { role: string; address: string }) {
  return (
    <div className="rounded-lg border border-brandHighlight/15 p-3">
      <p className="text-[0.6875rem] font-bold uppercase tracking-[0.1em] text-brandHighlight/60">{role}</p>
      <div className="mt-1 flex items-start justify-between gap-2">
        <p className="min-w-0 break-all font-mono text-xs text-brandHighlight">{address}</p>
        <CopyButton value={address} className="no-print" />
      </div>
    </div>
  )
}

interface Props {
  escrow: EscrowView
  index: number
  settlement: SettlementRecord | null | undefined
  loading: boolean
}

/** The printable document. Everything in it is read from the vault contract and its events. */
export function InvoiceSheet({ escrow, index, settlement, loading }: Props) {
  const [issuedAt] = useState(() => Math.floor(Date.now() / 1000))
  const milestone = escrow.milestones[index]
  const payee = settlement?.payee ?? escrow.contractor
  const amount = settlement?.amount ?? milestone.amount
  const invoiceNo = `ARC-INV-${escrow.id.toString()}-${index + 1}`

  return (
    <article className="bg-white p-6 text-brandHighlight sm:p-8" aria-label={`Invoice ${invoiceNo}`}>
      <header className="border-t-4 border-brandHighlight pt-4">
        <p className="display text-xl font-bold tracking-wide sm:text-2xl">ARCSTREAM-PQ | COMMERCIAL PAYMENT INVOICE</p>
        <p className="mt-1 text-sm text-brandHighlight/80">Irrevocable On-Chain Milestone Settlement Record</p>
      </header>

      <dl className="mt-6 grid gap-x-6 gap-y-4 sm:grid-cols-2">
        <Field label="Invoice number">
          <span className="font-mono font-semibold">{invoiceNo}</span>
        </Field>
        <Field label="Issue date">{when(issuedAt)}</Field>
        <Field label="Settlement timestamp">{loading ? 'Looking up...' : when(settlement?.timestamp ?? null)}</Field>
        <Field label="Network">
          {NETWORK.label} (Chain ID {NETWORK.chainId})
        </Field>
        <Field label="Vault contract">
          <span className="font-mono text-xs">{VAULT_ADDRESS ?? 'Not deployed'}</span>
        </Field>
        <Field label="Settlement transaction">
          {settlement ? (
            <a
              href={txUrl(settlement.txHash)}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-start gap-1 font-mono text-xs underline underline-offset-2"
            >
              {settlement.txHash}
              <ExternalLink className="no-print mt-0.5 size-3 shrink-0" />
            </a>
          ) : loading ? (
            'Looking up...'
          ) : (
            'Unavailable (the node did not return the payment event)'
          )}
        </Field>
      </dl>

      <section className="mt-6">
        <h3 className="text-[0.6875rem] font-bold uppercase tracking-[0.1em] text-brandHighlight/60">Parties</h3>
        <div className="mt-2 grid gap-3 sm:grid-cols-2">
          <Party role="Issuer / Client (employer)" address={escrow.employer} />
          <Party role="Vendor / Contractor (paid wallet)" address={payee} />
        </div>
      </section>

      <section className="mt-6">
        <h3 className="text-[0.6875rem] font-bold uppercase tracking-[0.1em] text-brandHighlight/60">Line item</h3>
        <div className="mt-2 overflow-x-auto rounded-lg border border-brandHighlight/15">
          <table className="w-full min-w-[34rem] text-left text-sm">
            <thead className="bg-brandMain text-[0.6875rem] font-bold uppercase tracking-[0.08em] text-brandHighlight/70">
              <tr>
                <th className="px-3 py-2">Milestone</th>
                <th className="px-3 py-2">Deliverable / description</th>
                <th className="px-3 py-2">Proof of work</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2 text-right">Total settled</th>
              </tr>
            </thead>
            <tbody>
              <tr className="align-top">
                <td className="px-3 py-3">
                  <p className="font-semibold tabular-nums">
                    {index + 1} of {escrow.milestoneCount}
                  </p>
                  <p className="mt-1 text-xs text-brandHighlight/80">{milestoneTitle(milestone.description)}</p>
                </td>
                <td className="max-w-64 whitespace-pre-wrap break-words px-3 py-3 text-xs">{milestone.description}</td>
                <td className="max-w-56 px-3 py-3">
                  {milestone.workProofHash ? (
                    <ProofViewer proof={milestone.workProofHash} compact />
                  ) : (
                    <span className="text-xs text-brandHighlight/70">None recorded</span>
                  )}
                </td>
                <td className="px-3 py-3 font-semibold">
                  Released &amp; Paid
                  {settlement?.kind === 'uncontested' && (
                    <span className="mt-1 block text-xs font-normal text-brandHighlight/70">
                      Claimed by the contractor after the review window
                    </span>
                  )}
                </td>
                <td className="px-3 py-3 text-right font-mono font-semibold tabular-nums">${fmtUsdc(amount)} USDC</td>
              </tr>
            </tbody>
            <tfoot>
              <tr className="border-t border-brandHighlight/15">
                <td colSpan={4} className="px-3 py-3 text-right text-xs font-bold uppercase tracking-[0.08em]">
                  Gross amount settled
                </td>
                <td className="px-3 py-3 text-right font-mono text-base font-bold tabular-nums">${fmtUsdc(amount)} USDC</td>
              </tr>
            </tfoot>
          </table>
        </div>
      </section>

      <section className="mt-6 rounded-lg border-2 border-brandHighlight p-4">
        <h3 className="text-[0.6875rem] font-bold uppercase tracking-[0.1em] text-brandHighlight/60">Cryptographic security seal</h3>
        {escrow.isPQProtected ? (
          <>
            <p className="mt-2 text-sm font-semibold">
              Secured by Arc Native SLH-DSA-SHA2-128s Precompile ({PQ_PRECOMPILE})
            </p>
            <p className="mt-1 text-xs text-brandHighlight/80">
              Employer release and refund on this escrow required a post-quantum SLH-DSA signature, verified onchain by
              Arc&apos;s native PQ Signature Verify precompile.
            </p>
            <p className="mt-2 break-all font-mono text-xs">
              PQ commitment {fingerprint(escrow.pqCommitment)} <span className="text-brandHighlight/60">({escrow.pqCommitment})</span>
            </p>
          </>
        ) : (
          <p className="mt-2 text-sm">Post-quantum signature protection was not enabled on this escrow.</p>
        )}
      </section>

      <footer className="mt-6 border-t border-brandHighlight/15 pt-4 text-xs leading-relaxed text-brandHighlight/80">
        <p>
          This invoice is a record of the on-chain USDC transfer for this milestone on the Arc Network blockchain, as
          written by the vault contract. That the work was delivered is attested by the employer&apos;s approval (or by
          the review window ending without one); the protocol does not verify the work itself.
        </p>
        <p className="mt-2">
          This is a payment record, not a tax invoice. It carries no tax registration numbers, VAT or sales tax
          breakdown, and is not legal or tax advice.
        </p>
      </footer>
    </article>
  )
}
