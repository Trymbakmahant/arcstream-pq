import { useState } from 'react'
import { ConnectKitButton } from 'connectkit'
import { useAccount, useSwitchChain } from 'wagmi'
import { getAddress, isAddress, type Hex } from 'viem'
import { Eye, Fingerprint, Loader2, Pencil, Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { ARC_CHAIN_ID } from '@/config'
import { VAULT_ADDRESS } from '@/contracts/vault'
import { useUsdcBalance } from '@/hooks/useUsdc'
import { useVaultActions } from '@/hooks/useVaultActions'
import { usePasskey } from '@/hooks/usePasskey'
import { fingerprint as shortHash } from '@/lib/pq'
import { BiometricError, createPqPublicKey, isInsideFrame } from '@/lib/webauthn'
import { fmtUsdc, parseUsdc } from '@/lib/money'
import { MAX_DESCRIPTION_LENGTH } from '@/lib/text'
import { RichText } from '@/components/RichText'

const MAX_MILESTONES = 50
const AMOUNT_PATTERN = /^\d*\.?\d{0,6}$/

interface Row {
  key: number
  amount: string
  description: string
  mode: 'write' | 'preview'
}

let rowKey = 0
const newRow = (): Row => ({ key: rowKey++, amount: '', description: '', mode: 'write' })

export function CreateEscrowCard({ onCreated }: { onCreated?: () => void }) {
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const { data: balance } = useUsdcBalance()
  const { createEscrow } = useVaultActions()
  const passkey = usePasskey()
  const [useBiometric, setUseBiometric] = useState(true)

  const [contractor, setContractor] = useState('')
  const [rows, setRows] = useState<Row[]>(() => [newRow(), newRow()])
  const [submitting, setSubmitting] = useState(false)

  const updateRow = (key: number, patch: Partial<Row>) =>
    setRows((current) => current.map((r) => (r.key === key ? { ...r, ...patch } : r)))

  const parsedAmounts = rows.map((r) => {
    if (!r.amount || r.amount === '.') return null
    try {
      const raw = parseUsdc(r.amount)
      return raw > 0n ? raw : null
    } catch {
      return null
    }
  })
  const total = parsedAmounts.reduce<bigint>((sum, a) => sum + (a ?? 0n), 0n)
  const allAmountsValid = parsedAmounts.every((a) => a !== null)
  const allDescriptions = rows.every((r) => r.description.trim().length > 0)

  const contractorValid = isAddress(contractor)
  const contractorIsSelf = contractorValid && !!address && contractor.toLowerCase() === address.toLowerCase()
  const insufficient = balance !== undefined && total > balance

  const problem = !VAULT_ADDRESS
    ? 'Vault contract is not deployed yet.'
    : !contractor
      ? 'Enter the contractor address.'
      : !contractorValid
        ? 'Contractor address is not valid.'
        : contractorIsSelf
          ? 'Contractor must be a different wallet than yours.'
          : !allAmountsValid
            ? 'Every milestone needs an amount above zero.'
            : !allDescriptions
              ? 'Every milestone needs a description.'
              : insufficient
                ? 'Your USDC balance is lower than the total.'
                : useBiometric && !passkey.registered
                  ? 'Set up your Touch ID / Face ID key, or turn off the biometric lock.'
                  : null

  const onCreate = async () => {
    if (problem || !contractorValid || !address || !VAULT_ADDRESS) return
    setSubmitting(true)
    try {
      let pqPublicKey: Hex = '0x'
      if (useBiometric) {
        try {
          pqPublicKey = await createPqPublicKey(address)
        } catch (error) {
          toast.error(error instanceof BiometricError ? error.message : 'Biometric authorization failed.')
          return
        }
      }
      const ok = await createEscrow(
        getAddress(contractor),
        parsedAmounts.map((a) => a ?? 0n),
        rows.map((r) => r.description.trim()),
        pqPublicKey,
      )
      if (ok) {
        setContractor('')
        setRows([newRow(), newRow()])
        onCreated?.()
      }
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className="rounded-2xl border border-brandSecondary bg-brandSecondary/20 p-6">
      <h2 className="display text-xl font-bold text-brandHighlight">Create Escrow</h2>
      <p className="mt-1 text-sm text-brandHighlight/80">
        Lock USDC up front. The contractor is paid per milestone once you approve their work.
      </p>

      <label htmlFor="contractor" className="label-caps mt-5 block text-brandHighlight/70">
        Contractor address
      </label>
      <input
        id="contractor"
        className="field mt-2 font-mono text-sm"
        placeholder="0x..."
        value={contractor}
        onChange={(e) => setContractor(e.target.value.trim())}
        spellCheck={false}
        autoComplete="off"
      />

      <div className="mt-5 flex items-center justify-between">
        <p className="label-caps text-brandHighlight/70">Milestones</p>
        <p className="text-xs tabular-nums text-brandHighlight/70">
          {rows.length}/{MAX_MILESTONES}
        </p>
      </div>

      <ul className="mt-2 space-y-4">
        {rows.map((row, index) => (
          <li key={row.key} className="rounded-2xl border border-brandSecondary/80 bg-brandMain p-4">
            <div className="mb-2 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brandHighlight text-sm font-semibold text-brandMain">
                  {index + 1}
                </span>
                <span className="text-sm font-semibold text-brandHighlight">Milestone {index + 1}</span>
              </div>

              <div className="relative w-40 shrink-0">
                <input
                  className="field py-1.5 pr-14 text-right tabular-nums"
                  inputMode="decimal"
                  placeholder="0.00"
                  aria-label={`Milestone ${index + 1} amount in USDC`}
                  value={row.amount}
                  onChange={(e) => {
                    const value = e.target.value
                    if (AMOUNT_PATTERN.test(value)) updateRow(row.key, { amount: value })
                  }}
                />
                <span className="pointer-events-none absolute inset-y-0 right-3 flex items-center text-xs font-semibold text-brandHighlight/70">
                  USDC
                </span>
              </div>

              <button
                type="button"
                className="flex size-11 shrink-0 items-center justify-center rounded-xl text-red-600 hover:bg-red-600/10 disabled:opacity-30"
                onClick={() => setRows((current) => current.filter((r) => r.key !== row.key))}
                disabled={rows.length === 1}
                aria-label={`Remove milestone ${index + 1}`}
              >
                <Trash2 className="size-4" />
              </button>
            </div>

            <div
              role="tablist"
              aria-label={`Milestone ${index + 1} description mode`}
              className="mb-2 inline-flex rounded-lg border border-brandHighlight/10 bg-brandSecondary/30 p-0.5"
            >
              {(
                [
                  { id: 'write', label: 'Write Details', icon: Pencil },
                  { id: 'preview', label: 'Preview Task', icon: Eye },
                ] as const
              ).map(({ id, label, icon: Icon }) => (
                <button
                  key={id}
                  type="button"
                  role="tab"
                  aria-selected={row.mode === id}
                  onClick={() => updateRow(row.key, { mode: id })}
                  className={`inline-flex min-h-9 items-center gap-1.5 rounded-md px-3 text-xs transition-all ${
                    row.mode === id
                      ? 'bg-brandHighlight font-medium text-brandMain shadow-sm'
                      : 'text-brandHighlight/70 hover:text-brandHighlight'
                  }`}
                >
                  <Icon className="size-3.5" />
                  {label}
                </button>
              ))}
            </div>

            {row.mode === 'write' ? (
              <>
                <textarea
                  rows={3}
                  className="w-full resize-y rounded-xl border border-brandHighlight/20 bg-white p-3 text-sm text-brandHighlight outline-none placeholder:text-brandHighlight/45 focus:border-brandSecondary focus:ring-[3px] focus:ring-brandSecondary/55"
                  placeholder="Describe deliverables, acceptance criteria, or links for this milestone..."
                  aria-label={`Milestone ${index + 1} description`}
                  value={row.description}
                  maxLength={MAX_DESCRIPTION_LENGTH}
                  onChange={(e) => updateRow(row.key, { description: e.target.value })}
                />
                <p className="mt-1 flex justify-between gap-3 text-xs text-brandHighlight/70">
                  <span>First line is the milestone title. Use - or 1. for lists. Links are clickable.</span>
                  <span className="tabular-nums">
                    {row.description.length}/{MAX_DESCRIPTION_LENGTH}
                  </span>
                </p>
              </>
            ) : (
              <div className="min-h-24 rounded-xl border border-brandHighlight/20 bg-white p-3">
                {row.description.trim() ? (
                  <RichText text={row.description} />
                ) : (
                  <p className="text-sm text-brandHighlight/60">Nothing to preview yet. Switch to Write Details.</p>
                )}
              </div>
            )}
          </li>
        ))}
      </ul>

      <button
        type="button"
        className="btn-ghost mt-3"
        disabled={rows.length >= MAX_MILESTONES}
        onClick={() => setRows((current) => [...current, newRow()])}
      >
        <Plus className="size-4" />
        Add Milestone
      </button>

      <div className="mt-5 rounded-xl border border-brandHighlight/15 bg-brandMain p-4">
        <label className="flex min-h-11 cursor-pointer items-start gap-3">
          <input
            type="checkbox"
            className="mt-1 size-4 accent-brandHighlight"
            checked={useBiometric}
            onChange={(e) => setUseBiometric(e.target.checked)}
          />
          <span className="text-sm font-semibold text-brandHighlight">
            Secure with Face ID / Touch ID (post-quantum signature lock)
          </span>
        </label>
        {useBiometric && (
          <div className="mt-2 space-y-2 pl-7 text-sm text-brandHighlight/80">
            {passkey.registered && passkey.fingerprint ? (
              <p className="flex flex-wrap items-center gap-2 font-medium text-brandHighlight">
                <Fingerprint className="size-4" />
                Biometric Key: Registered
                <span className="rounded-full bg-brandSecondary/60 px-2.5 py-0.5 font-mono text-xs">
                  {shortHash(passkey.fingerprint)}
                </span>
              </p>
            ) : (
              <button
                type="button"
                className="btn-ghost"
                disabled={!isConnected || passkey.busy || !passkey.supported}
                onClick={() => {
                  void passkey.register()
                }}
              >
                {passkey.busy ? <Loader2 className="size-4 animate-spin" /> : <Fingerprint className="size-4" />}
                Set Up Touch ID / Face ID Key
              </button>
            )}
            {!passkey.supported && <p>This browser does not support passkeys.</p>}
            {isInsideFrame() && (
              <p>Browsers often block Touch ID inside the Arc Studio preview. Open the app in its own tab to use it.</p>
            )}
            <p>
              Touch ID / Face ID is then required for the employer to release a payout or refund. The wallet key
              alone cannot do either on this escrow. Arc verifies a post-quantum SLH-DSA signature that your
              passkey unlocks. A stolen wallet key could still approve milestones, which pays the contractor.
            </p>
          </div>
        )}
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-4 border-t border-brandHighlight/15 pt-5">
        <div>
          <p className="label-caps text-brandHighlight/70">Total to deposit</p>
          <p className="display text-2xl font-black tabular-nums text-brandHighlight">
            {fmtUsdc(total)} <span className="text-base font-medium">USDC</span>
          </p>
          {balance !== undefined && (
            <p className="text-xs tabular-nums text-brandHighlight/70">Balance {fmtUsdc(balance)} USDC</p>
          )}
        </div>

        {!isConnected ? (
          <ConnectKitButton.Custom>
            {({ show }) => (
              <button type="button" className="btn-primary rounded-xl px-6 py-3" onClick={show}>
                Connect Wallet
              </button>
            )}
          </ConnectKitButton.Custom>
        ) : chainId !== ARC_CHAIN_ID ? (
          <button
            type="button"
            className="btn-primary rounded-xl px-6 py-3"
            onClick={() => switchChain({ chainId: ARC_CHAIN_ID })}
          >
            Switch to Arc Testnet
          </button>
        ) : (
          <button
            type="button"
            className="btn-primary rounded-xl px-6 py-3"
            disabled={!!problem || submitting}
            onClick={() => {
              void onCreate()
            }}>
            {submitting && <Loader2 className="size-4 animate-spin" />}
            Approve &amp; Deposit
          </button>
        )}
      </div>

      {isConnected && chainId === ARC_CHAIN_ID && problem && (
        <p className="mt-3 text-sm text-brandHighlight/80">{problem}</p>
      )}
      <p className="mt-3 text-xs text-brandHighlight/70">
        Two wallet confirmations: first the USDC allowance, then the escrow deposit.
      </p>
    </section>
  )
}
