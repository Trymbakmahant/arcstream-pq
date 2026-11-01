import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ConnectKitButton } from 'connectkit'
import { useAccount, useSwitchChain } from 'wagmi'
import { getAddress, isAddress, type Hex } from 'viem'
import { Droplets, Eye, Fingerprint, Loader2, Pencil, Plus, Trash2, TriangleAlert } from 'lucide-react'
import { toast } from 'sonner'
import { ARC_CHAIN_ID } from '@/config'
import { VAULT_ADDRESS } from '@/contracts/vault'
import { DAY_SECONDS, DEFAULT_REVIEW_DAYS, REVIEW_WINDOW_DAYS } from '@/lib/inspection'
import { NETWORK } from '@/lib/network'
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

export function CreateEscrowCard({
  onCreated,
  onFund,
  embedded = false,
}: {
  onCreated?: () => void
  onFund?: () => void
  /** Inside a modal that already has a title and its own frame. */
  embedded?: boolean
}) {
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const { data: balance } = useUsdcBalance()
  const { createEscrow } = useVaultActions()
  const passkey = usePasskey()
  const [useBiometric, setUseBiometric] = useState(true)
  const [reviewDays, setReviewDays] = useState<number>(DEFAULT_REVIEW_DAYS)

  const [contractor, setContractor] = useState('')
  const [rows, setRows] = useState<Row[]>(() => [newRow(), newRow()])
  const [submitting, setSubmitting] = useState(false)
  const [shakeCount, setShakeCount] = useState(0)
  const [showErrorAlert, setShowErrorAlert] = useState(false)

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

  const contractorValid = isAddress(contractor)
  const contractorIsSelf = contractorValid && !!address && contractor.toLowerCase() === address.toLowerCase()

  // Safe buffer for Arc native transaction gas fees (~0.01 USDC)
  const GAS_BUFFER = 10_000n
  const hasGasShortage = balance !== undefined && total > 0n && balance >= total && balance < total + GAS_BUFFER
  const isWrongChain = isConnected && chainId !== ARC_CHAIN_ID

  interface ValidationError {
    type: 'vault' | 'network' | 'contractor' | 'milestone_empty' | 'milestone_amount' | 'milestone_description' | 'biometric' | 'balance' | 'gas'
    message: string
    milestoneIndex?: number
    action?: 'fund' | 'passkey' | 'remove_milestone' | 'switch_network'
  }

  const getValidation = (): ValidationError | null => {
    if (!VAULT_ADDRESS) {
      return { type: 'vault', message: `Vault contract is not deployed yet on ${NETWORK.label}.` }
    }
    if (isWrongChain) {
      return {
        type: 'network',
        message: `Please switch your wallet network to ${NETWORK.label}.`,
        action: 'switch_network',
      }
    }
    if (!contractor) {
      return {
        type: 'contractor',
        message: 'Contractor address is missing. Please enter the contractor wallet address (0x...).',
      }
    }
    if (!contractorValid) {
      return {
        type: 'contractor',
        message: 'Contractor address is invalid. Please enter a valid 0x Ethereum address.',
      }
    }
    if (contractorIsSelf) {
      return {
        type: 'contractor',
        message: 'Contractor must be a different wallet address than your own.',
      }
    }

    // Validate each milestone individually
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i]
      const hasAmount = !!row.amount && row.amount !== '.'
      const hasDescription = row.description.trim().length > 0

      // If completely empty and more than 1 milestone exists
      if (!hasAmount && !hasDescription) {
        if (rows.length > 1) {
          return {
            type: 'milestone_empty',
            message: `Milestone ${i + 1} is empty — please fill in details or delete it.`,
            milestoneIndex: i,
            action: 'remove_milestone',
          }
        }
        return {
          type: 'milestone_amount',
          message: 'Milestone 1: You didn’t put an amount. Please enter a USDC amount.',
          milestoneIndex: 0,
        }
      }

      if (!hasAmount) {
        return {
          type: 'milestone_amount',
          message: `Milestone ${i + 1}: You didn’t put an amount. Please enter the USDC amount.`,
          milestoneIndex: i,
        }
      }

      try {
        const raw = parseUsdc(row.amount)
        if (raw <= 0n) {
          return {
            type: 'milestone_amount',
            message: `Milestone ${i + 1}: Amount must be greater than 0 USDC.`,
            milestoneIndex: i,
          }
        }
      } catch {
        return {
          type: 'milestone_amount',
          message: `Milestone ${i + 1}: Invalid USDC amount format.`,
          milestoneIndex: i,
        }
      }

      if (!hasDescription) {
        return {
          type: 'milestone_description',
          message: `Milestone ${i + 1}: Description is missing. Please describe the deliverable.`,
          milestoneIndex: i,
        }
      }
    }

    if (balance !== undefined && balance === 0n) {
      return {
        type: 'balance',
        message: `Your USDC balance is 0.00. Please fund your wallet with ${NETWORK.label} USDC first.`,
        action: 'fund',
      }
    }

    if (balance !== undefined && total > balance) {
      return {
        type: 'balance',
        message: `Insufficient USDC: you need ${fmtUsdc(total)} USDC but only have ${fmtUsdc(balance)} USDC.`,
        action: 'fund',
      }
    }

    if (hasGasShortage) {
      return {
        type: 'gas',
        message: 'You need ~0.01 USDC more to cover transaction gas fees on Arc.',
        action: 'fund',
      }
    }

    if (useBiometric && !passkey.registered) {
      return {
        type: 'biometric',
        message: 'Biometrics required: Click "Set Up Touch ID / Face ID Key" below or turn off the biometric lock.',
        action: 'passkey',
      }
    }

    return null
  }

  const validation = getValidation()

  const handleButtonClick = async () => {
    if (validation) {
      setShakeCount((c) => c + 1)
      setShowErrorAlert(true)
      toast.error(validation.message)
      return
    }
    await onCreate()
  }

  const onCreate = async () => {
    if (validation || !contractorValid || !address || !VAULT_ADDRESS) return
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
        reviewDays * DAY_SECONDS,
      )
      if (ok) {
        setContractor('')
        setRows([newRow(), newRow()])
        setShowErrorAlert(false)
        onCreated?.()
      }
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className={embedded ? 'p-6' : 'neu-card rounded-2xl border border-white/5 p-6'}>
      {!embedded && (
        <div className="mb-4">
          <h2 className="display text-xl font-bold text-white">Create Escrow</h2>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
            <span className="neu-sunken inline-flex items-center gap-1.5 rounded-full border border-white/5 px-2.5 py-0.5 font-medium text-zinc-300 font-mono">
              <span className={`size-2 rounded-full ${NETWORK.isMainnet ? 'bg-emerald-500 shadow-[0_0_8px_#10b981]' : 'bg-neonLime shadow-[0_0_8px_#d4ff3f]'}`} />
              {NETWORK.label}
            </span>
            <span className="neu-sunken rounded-md border border-white/5 px-2 py-0.5 font-mono text-[11px] text-zinc-400">
              Network ID: <strong className="text-white">{NETWORK.chainId}</strong>
            </span>
            <span className="neu-sunken rounded-md border border-white/5 px-2 py-0.5 font-mono text-[11px] text-zinc-400" title={NETWORK.rpcUrl}>
              RPC: <strong className="text-white">{NETWORK.rpcUrl.replace('https://', '')}</strong>
            </span>
          </div>
        </div>
      )}
      <p className="text-sm text-zinc-400">
        Lock USDC up front. The contractor is paid per milestone once you approve their work.
      </p>

      {isConnected && chainId !== ARC_CHAIN_ID && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-200">
          <div className="flex items-center gap-2">
            <TriangleAlert className="size-4 shrink-0 text-amber-400" />
            <span>
              Wallet network (Chain ID: <strong>{chainId ?? 'unknown'}</strong>) does not match app target (<strong>{NETWORK.label} • Chain ID: {NETWORK.chainId}</strong>).
            </span>
          </div>
          <button
            type="button"
            className="rounded-lg bg-amber-500/20 border border-amber-500/40 px-3 py-1 font-semibold text-amber-300 transition-opacity hover:opacity-90"
            onClick={() => switchChain({ chainId: ARC_CHAIN_ID })}
          >
            Switch to {NETWORK.label}
          </button>
        </div>
      )}

      <label htmlFor="contractor" className="label-caps mt-5 block text-zinc-500">
        Contractor address
      </label>
      <input
        id="contractor"
        className={`field mt-2 font-mono text-sm transition-all ${
          showErrorAlert && validation?.type === 'contractor'
            ? 'border-red-500/80 bg-red-950/20 ring-2 ring-red-500/40 text-red-200 placeholder:text-red-300/40'
            : ''
        }`}
        placeholder="0x..."
        value={contractor}
        onChange={(e) => setContractor(e.target.value.trim())}
        spellCheck={false}
        autoComplete="off"
      />
      {showErrorAlert && validation?.type === 'contractor' && (
        <p className="mt-1.5 flex items-center gap-1.5 text-xs text-red-400 font-medium">
          <TriangleAlert className="size-3.5 shrink-0" />
          {validation.message}
        </p>
      )}

      <div className="mt-5 flex items-center justify-between">
        <p className="label-caps text-zinc-500">Milestones</p>
        <p className="text-xs tabular-nums text-zinc-500 font-mono">
          {rows.length}/{MAX_MILESTONES}
        </p>
      </div>

      <ul className="mt-2 space-y-4">
        {rows.map((row, index) => {
          const isInvalidRow = showErrorAlert && validation?.milestoneIndex === index
          return (
            <li
              key={row.key}
              className={`neu-sunken rounded-2xl border p-4 transition-all ${
                isInvalidRow
                  ? 'border-red-500/80 bg-red-950/20 ring-2 ring-red-500/30'
                  : 'border-white/5'
              }`}
            >
              {isInvalidRow && (
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-xl bg-red-500/20 border border-red-500/30 px-3 py-2 text-xs text-red-200">
                  <div className="flex items-center gap-1.5 font-medium">
                    <TriangleAlert className="size-3.5 text-red-400 shrink-0" />
                    <span>{validation.message}</span>
                  </div>
                  {validation.action === 'remove_milestone' && (
                    <button
                      type="button"
                      className="font-semibold text-red-300 hover:text-white underline ml-2 shrink-0"
                      onClick={() => setRows((current) => current.filter((r) => r.key !== row.key))}
                    >
                      Delete this milestone
                    </button>
                  )}
                </div>
              )}
              <div className="mb-2 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <span className="neu-card flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border border-neonLime/30 text-sm font-semibold text-neonLime">
                  {index + 1}
                </span>
                <span className="text-sm font-semibold text-white">Milestone {index + 1}</span>
              </div>

              <div className="relative w-40 shrink-0">
                <input
                  className="field py-1.5 pr-14 text-right tabular-nums font-mono text-sm"
                  inputMode="decimal"
                  placeholder="0.00"
                  aria-label={`Milestone ${index + 1} amount in USDC`}
                  value={row.amount}
                  onChange={(e) => {
                    const value = e.target.value
                    if (AMOUNT_PATTERN.test(value)) updateRow(row.key, { amount: value })
                  }}
                />
                <span className="pointer-events-none absolute inset-y-0 right-3 flex items-center text-xs font-semibold text-zinc-500">
                  USDC
                </span>
              </div>

              <button
                type="button"
                className="flex size-11 shrink-0 items-center justify-center rounded-xl text-zinc-500 hover:text-red-400 hover:bg-white/5 disabled:opacity-30 transition-colors"
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
              className="neu-card mb-2 inline-flex rounded-lg border border-white/5 p-0.5"
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
                      ? 'neu-sunken border border-neonLime/30 font-medium text-neonLime shadow-glow-lime'
                      : 'text-zinc-500 hover:text-white'
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
                  className="field min-h-24 resize-y text-sm"
                  placeholder="Describe deliverables, acceptance criteria, or links for this milestone..."
                  aria-label={`Milestone ${index + 1} description`}
                  value={row.description}
                  maxLength={MAX_DESCRIPTION_LENGTH}
                  onChange={(e) => updateRow(row.key, { description: e.target.value })}
                />
                <p className="mt-1 flex justify-between gap-3 text-xs text-zinc-500">
                  <span>First line is the milestone title. Use - or 1. for lists. Links are clickable.</span>
                  <span className="tabular-nums font-mono">
                    {row.description.length}/{MAX_DESCRIPTION_LENGTH}
                  </span>
                </p>
              </>
            ) : (
              <div className="neu-sunken min-h-24 rounded-xl border border-white/5 p-3 text-zinc-200">
                {row.description.trim() ? (
                  <RichText text={row.description} />
                ) : (
                  <p className="text-sm text-zinc-500">Nothing to preview yet. Switch to Write Details.</p>
                )}
              </div>
            )}
          </li>
          )
        })}
      </ul>

      <button
        type="button"
        className="btn-ghost mt-3"
        disabled={rows.length >= MAX_MILESTONES}
        onClick={() => setRows((current) => [...current, newRow()])}
      >
        <Plus className="size-4 text-neonLime" />
        Add Milestone
      </button>

      <div
        className={`neu-card mt-5 rounded-xl border p-4 transition-all ${
          showErrorAlert && validation?.type === 'biometric'
            ? 'border-red-500/80 bg-red-950/20 ring-2 ring-red-500/30'
            : 'border-white/5'
        }`}
      >
        <label className="flex min-h-11 cursor-pointer items-start gap-3">
          <input
            type="checkbox"
            className="mt-1 size-4 accent-[#d4ff3f]"
            checked={useBiometric}
            onChange={(e) => setUseBiometric(e.target.checked)}
          />
          <span className="text-sm font-semibold text-white">
            Secure with Face ID / Touch ID (post-quantum signature lock)
          </span>
        </label>
        {showErrorAlert && validation?.type === 'biometric' && (
          <div className="mt-2 mb-2 flex items-center justify-between gap-2 rounded-xl bg-red-500/20 border border-red-500/30 px-3 py-2 text-xs text-red-200">
            <div className="flex items-center gap-1.5 font-medium">
              <TriangleAlert className="size-3.5 text-red-400 shrink-0" />
              <span>Biometric passkey is required! Click the button below to register, or uncheck the biometric lock.</span>
            </div>
          </div>
        )}
        {useBiometric && (
          <div className="mt-2 space-y-2 pl-7 text-sm text-zinc-400">
            {passkey.registered && passkey.fingerprint ? (
              <p className="flex flex-wrap items-center gap-2 font-medium text-neonPink">
                <Fingerprint className="size-4" />
                Biometric Key: Registered
                <span className="neu-sunken rounded-full border border-neonPink/40 px-2.5 py-0.5 font-mono text-xs text-neonPink shadow-glow-pink">
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
                {passkey.busy ? <Loader2 className="size-4 animate-spin" /> : <Fingerprint className="size-4 text-neonPink" />}
                Set Up Touch ID / Face ID Key
              </button>
            )}
            {!passkey.supported && <p>This browser does not support passkeys.</p>}
            {isInsideFrame() && (
              <p>Browsers often block Touch ID inside the Arc Studio preview. Open the app in its own tab to use it.</p>
            )}
            <p className="text-xs text-zinc-500">
              Touch ID / Face ID is then required for the employer to release a payout or refund. The wallet key
              alone cannot do either on this escrow. Arc verifies a post-quantum SLH-DSA signature that your
              passkey unlocks. A stolen wallet key could still approve milestones, which pays the contractor.
            </p>
          </div>
        )}
      </div>

      <div className="neu-card mt-4 rounded-xl border border-white/5 p-4">
        <label htmlFor="review-window" className="text-sm font-semibold text-white">
          Review window
        </label>
        <div className="mt-2 flex flex-wrap items-center gap-3">
          <select
            id="review-window"
            className="field w-auto min-w-36 font-mono text-sm"
            value={reviewDays}
            onChange={(e) => setReviewDays(Number(e.target.value))}
          >
            {REVIEW_WINDOW_DAYS.map((d) => (
              <option key={d} value={d} className="bg-[#090c12] text-white">
                {d} {d === 1 ? 'day' : 'days'}
                {d === DEFAULT_REVIEW_DAYS ? ' (default)' : ''}
              </option>
            ))}
          </select>
          <p className="min-w-0 flex-1 text-xs text-zinc-400">
            After the contractor submits proof, you have this long to approve it. If you do nothing, the
            contractor can claim that milestone&apos;s payout once the window ends.
          </p>
        </div>
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-4 border-t border-white/5 pt-5">
        <div>
          <p className="label-caps text-zinc-500">Total to deposit</p>
          <p className="display text-2xl font-black tabular-nums text-white">
            {fmtUsdc(total)} <span className="text-base font-medium text-neonLime">USDC</span>
          </p>
          {balance !== undefined && (
            <p className="text-xs tabular-nums text-zinc-500 font-mono">Balance {fmtUsdc(balance)} USDC</p>
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
            Switch to {NETWORK.label}
          </button>
        ) : (
          <motion.button
            type="button"
            className="btn-primary rounded-xl px-6 py-3 font-semibold shadow-lg shadow-neonLime/10"
            animate={
              shakeCount > 0
                ? {
                    x: [0, -14, 14, -10, 10, -6, 6, -2, 2, 0],
                    transition: { duration: 0.45, ease: 'easeInOut' },
                  }
                : undefined
            }
            key={shakeCount}
            disabled={submitting}
            onClick={() => {
              void handleButtonClick()
            }}
          >
            {submitting && <Loader2 className="size-4 animate-spin" />}
            Approve &amp; Deposit
          </motion.button>
        )}
      </div>

      <AnimatePresence>
        {isConnected && showErrorAlert && validation && (
          <motion.div
            initial={{ opacity: 0, y: -6, scale: 0.98 }}
            animate={{
              opacity: 1,
              y: 0,
              scale: 1,
              x: [0, -10, 10, -8, 8, -4, 4, 0],
            }}
            exit={{ opacity: 0, y: -6, scale: 0.98 }}
            transition={{ duration: 0.4 }}
            className="neu-sunken mt-4 flex flex-wrap items-center justify-between gap-3 rounded-2xl border-2 border-red-500/80 bg-red-950/40 p-4 text-sm text-red-200 shadow-[0_0_24px_rgba(239,68,68,0.35)]"
          >
            <div className="flex items-center gap-3">
              <div className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-red-500/20 text-red-400 border border-red-500/40">
                <TriangleAlert className="size-5 text-red-400 animate-pulse" />
              </div>
              <div>
                <p className="font-bold text-red-400 tracking-wider uppercase text-[11px] font-mono">
                  Attention Required
                </p>
                <p className="mt-0.5 font-semibold text-white">{validation.message}</p>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              {validation.action === 'remove_milestone' && validation.milestoneIndex !== undefined && (
                <button
                  type="button"
                  className="rounded-xl bg-red-500/20 border border-red-500/40 px-3 py-1.5 text-xs font-semibold text-red-200 hover:bg-red-500/30 transition-colors"
                  onClick={() => {
                    const idx = validation.milestoneIndex!
                    setRows((current) => current.filter((_, i) => i !== idx))
                  }}
                >
                  <Trash2 className="size-3.5 inline mr-1" />
                  Delete Milestone {validation.milestoneIndex + 1}
                </button>
              )}
              {validation.action === 'passkey' && (
                <button
                  type="button"
                  className="btn-pink px-3 py-1.5 text-xs font-semibold shadow-glow-pink"
                  onClick={() => {
                    void passkey.register()
                  }}
                >
                  <Fingerprint className="size-3.5 inline mr-1" />
                  Set Up Touch ID Now
                </button>
              )}
              {validation.action === 'fund' && onFund && (
                <button
                  type="button"
                  className="btn-pink px-3 py-1.5 text-xs font-semibold"
                  onClick={onFund}
                >
                  <Droplets className="size-3.5 inline mr-1" />
                  Fund with USDC
                </button>
              )}
              {validation.action === 'switch_network' && (
                <button
                  type="button"
                  className="rounded-xl bg-amber-500/20 border border-amber-500/40 px-3 py-1.5 text-xs font-semibold text-amber-200 hover:bg-amber-500/30"
                  onClick={() => switchChain({ chainId: ARC_CHAIN_ID })}
                >
                  Switch to {NETWORK.label}
                </button>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      <p className="mt-3 text-xs text-zinc-500 font-mono">
        Two wallet confirmations: first the USDC allowance, then the escrow deposit.
      </p>
    </section>
  )
}
