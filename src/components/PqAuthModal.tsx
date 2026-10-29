import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { useAccount } from 'wagmi'
import { Check, Fingerprint, Loader2, ShieldCheck, TriangleAlert, Wallet, X } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { VAULT_ADDRESS } from '@/contracts/vault'
import type { EscrowView } from '@/hooks/useEscrows'
import { usePasskey } from '@/hooks/usePasskey'
import { useVaultActions } from '@/hooks/useVaultActions'
import { fmtUsdc, shortAddress } from '@/lib/money'
import { fingerprint as shortHash } from '@/lib/pq'
import { BiometricError, signWithBiometricPQKey } from '@/lib/webauthn'

export interface PqAuthRequest {
  kind: 'release' | 'approve-release' | 'refund'
  escrow: EscrowView
  index?: number
}

interface Props {
  request: PqAuthRequest | null
  onClose: () => void
}

export function PqAuthModal({ request, onClose }: Props) {
  return (
    <AnimatePresence>
      {request && (
        <motion.div
          key="pq-auth"
          className="fixed inset-0 z-[9500] flex items-center justify-center bg-brandHighlight/80 p-4 backdrop-blur-sm"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          role="dialog"
          aria-modal="true"
          aria-label="Biometric authorization"
        >
          <AuthPanel request={request} onClose={onClose} />
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function AuthPanel({ request, onClose }: { request: PqAuthRequest; onClose: () => void }) {
  const { address, chainId, isConnected } = useAccount()
  const passkey = usePasskey()
  const actions = useVaultActions()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const { escrow, kind, index } = request
  const isEmployer = !!address && address.toLowerCase() === escrow.employer.toLowerCase()
  const walletOk = isConnected && chainId === ARC_CHAIN_ID && isEmployer
  const biometricReady = passkey.registered
  const isMilestoneAction = kind !== 'refund'
  const milestone = isMilestoneAction && index !== undefined ? escrow.milestones[index] : undefined
  const action = isMilestoneAction ? (index ?? 0) : escrow.milestoneCount

  const authorize = async () => {
    if (!address || !VAULT_ADDRESS) return
    setBusy(true)
    setError(null)
    try {
      const proof = await signWithBiometricPQKey({
        userAddress: address,
        vault: VAULT_ADDRESS,
        chainId: ARC_CHAIN_ID,
        escrowId: escrow.id,
        action,
        publicKey: escrow.pqPublicKey,
      })
      onClose()
      if (kind === 'release') await actions.releaseMilestone(escrow.id, action, proof)
      else if (kind === 'approve-release') await actions.approveAndRelease(escrow.id, action, proof)
      else await actions.refundRemaining(escrow.id, proof)
    } catch (e) {
      setError(e instanceof BiometricError ? e.message : 'Authorization failed. Please try again.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <motion.div
      className="w-full max-w-md rounded-2xl border border-brandSecondary bg-brandMain p-6 shadow-2xl"
      initial={{ y: 16, scale: 0.98 }}
      animate={{ y: 0, scale: 1 }}
      exit={{ y: 16, scale: 0.98 }}
      transition={{ type: 'spring', stiffness: 380, damping: 32 }}
      onClick={(e) => e.stopPropagation()}
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="label-caps text-brandHighlight/70">
            Escrow #{escrow.id.toString()} {isMilestoneAction ? `/ Milestone ${action + 1}` : ''}
          </p>
          <h2 className="display mt-1 text-xl font-bold text-brandHighlight">
            {kind === 'release' ? 'Authorize payout release' : kind === 'approve-release' ? 'Authorize approval and release' : 'Authorize refund'}
          </h2>
          {milestone && (
            <p className="mt-1 text-sm tabular-nums text-brandHighlight/80">{fmtUsdc(milestone.amount)} USDC to the contractor</p>
          )}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="flex size-11 items-center justify-center rounded-full text-brandHighlight hover:bg-brandSecondary/40"
          aria-label="Close"
        >
          <X className="size-5" />
        </button>
      </div>

      <ol className="mt-5 space-y-3">
        <Layer
          icon={<Wallet className="size-4" />}
          title="1. Wallet signature (ECDSA)"
          detail={address ? shortAddress(address) : 'No wallet connected'}
          ok={walletOk}
          okLabel="Verified"
          failLabel={
            !isConnected
              ? 'Connect wallet'
              : chainId !== ARC_CHAIN_ID
                ? 'Wrong network'
                : 'Not the employer'
          }
        />
        <Layer
          icon={<Fingerprint className="size-4" />}
          title="2. Biometric unlock (Touch ID / Face ID)"
          detail="Releases your post-quantum signing seed on this device"
          ok={biometricReady}
          okLabel="Ready"
          failLabel="Not set up"
        />
        <Layer
          icon={<ShieldCheck className="size-4" />}
          title="3. Post-quantum signature (SLH-DSA, FIPS 205)"
          detail={`Escrow key ${shortHash(escrow.pqCommitment)}, checked by Arc's precompile`}
          ok={biometricReady}
          okLabel="Ready"
          failLabel="Needs step 2"
        />
      </ol>

      {error && (
        <p className="mt-4 flex items-start gap-2 rounded-xl border border-brandHighlight bg-brandMain p-3 text-sm font-medium text-brandHighlight">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          {error}
        </p>
      )}

      {!passkey.registered && (
        <button
          type="button"
          className="btn-ghost mt-4 w-full"
          disabled={passkey.busy || !passkey.supported}
          onClick={() => {
            void passkey.register()
          }}
        >
          {passkey.busy && <Loader2 className="size-4 animate-spin" />}
          Set Up Touch ID / Face ID Key
        </button>
      )}

      <button
        type="button"
        className="btn-primary mt-4 w-full rounded-xl py-3"
        disabled={busy || !walletOk || !biometricReady}
        onClick={() => {
          void authorize()
        }}
      >
        {busy ? <Loader2 className="size-4 animate-spin" /> : <Fingerprint className="size-4" />}
        {busy ? 'Signing, this takes a few seconds...' : 'Sign with Post-Quantum Key and Continue'}
      </button>

      <p className="mt-3 text-xs text-brandHighlight/70">
        Your device asks for Touch ID or Face ID. The post-quantum key is then derived in memory and signs this
        one action. Your wallet then sends the signature, and Arc verifies it before any funds move. The wallet
        key alone cannot release or refund this escrow, but it can still approve milestones.
      </p>
    </motion.div>
  )
}

function Layer({
  icon,
  title,
  detail,
  ok,
  okLabel,
  failLabel,
}: {
  icon: React.ReactNode
  title: string
  detail: string
  ok: boolean
  okLabel: string
  failLabel: string
}) {
  return (
    <li className="flex items-center gap-3 rounded-xl border border-brandSecondary/70 bg-brandSecondary/20 p-3">
      <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-brandHighlight text-brandMain">
        {icon}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-brandHighlight">{title}</p>
        <p className="truncate font-mono text-xs text-brandHighlight/70">{detail}</p>
      </div>
      <span
        className={`inline-flex shrink-0 items-center gap-1 rounded-full px-3 py-1 text-[0.6875rem] font-bold tracking-[0.06em] ${
          ok ? 'bg-brandHighlight text-brandMain' : 'border border-brandHighlight/40 text-brandHighlight'
        }`}
      >
        {ok && <Check className="size-3" />}
        {ok ? okLabel : failLabel}
      </span>
    </li>
  )
}
