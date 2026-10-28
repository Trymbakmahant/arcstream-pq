import { bytesToHex, hexToBytes, keccak256, toHex, type Address, type Hex } from 'viem'
import { buildProof, computeRoot, type PqContext, type PqRecord } from '@/lib/pq'

/**
 * Touch ID / Face ID (WebAuthn passkey) as the unlock for the hash-based one-time secrets.
 *
 * What this is: the passkey (a P-256 platform credential) proves a person is present and verified on
 * this device. When the browser supports the WebAuthn PRF extension, the passkey also derives a stable
 * 32-byte master secret, so nothing secret is stored. Without PRF, a random master secret is kept in
 * localStorage and the biometric prompt only gates access to it.
 *
 * What it is not: the passkey signature is never sent onchain and P-256 is not post-quantum. The
 * onchain check is the keccak256 Merkle proof of a one-time secret (see lib/pq.ts).
 */

export type BiometricErrorCode =
  | 'UNSUPPORTED'
  | 'NOT_REGISTERED'
  | 'CANCELLED'
  | 'PRF_UNAVAILABLE'
  | 'KEY_MISMATCH'
  | 'NO_RECORD'

export class BiometricError extends Error {
  readonly code: BiometricErrorCode
  constructor(code: BiometricErrorCode, message: string) {
    super(message)
    this.name = 'BiometricError'
    this.code = code
  }
}

interface StoredPasskey {
  credentialId: string
  rpId: string
  prf: boolean
  fallbackMaster?: Hex
  createdAt: number
}

const PRF_SALT = new TextEncoder().encode('arcstream-pq/v1/master')
const passkeyKey = (address: string) => `arcstream.passkey.v1.${address.toLowerCase()}`
const recordsKey = (address: string) => `arcstream.pq-records.v1.${address.toLowerCase()}`
const CHANGE_EVENT = 'arcstream:passkey-changed'

const b64urlEncode = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

const b64urlDecode = (value: string): Uint8Array<ArrayBuffer> => {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=')
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))
}

const randomBytes = (length: number): Uint8Array<ArrayBuffer> => crypto.getRandomValues(new Uint8Array(length))

export const isInsideFrame = () => typeof window !== 'undefined' && window.self !== window.top

export function isPasskeySupported(): boolean {
  return typeof window !== 'undefined' && !!window.PublicKeyCredential && !!navigator.credentials
}

function readPasskey(address: string): StoredPasskey | null {
  try {
    const raw = localStorage.getItem(passkeyKey(address))
    return raw ? (JSON.parse(raw) as StoredPasskey) : null
  } catch {
    return null
  }
}

function notify() {
  window.dispatchEvent(new Event(CHANGE_EVENT))
}

/** Stable string for useSyncExternalStore: the credential id, or an empty string when none is registered. */
export const passkeySnapshot = (address: string | undefined): string =>
  address ? (readPasskey(address)?.credentialId ?? '') : ''

export function subscribePasskey(callback: () => void): () => void {
  window.addEventListener(CHANGE_EVENT, callback)
  window.addEventListener('storage', callback)
  return () => {
    window.removeEventListener(CHANGE_EVENT, callback)
    window.removeEventListener('storage', callback)
  }
}

/** keccak256 of the credential id, shown as the biometric key fingerprint. */
export function passkeyFingerprint(address: string): Hex | null {
  const stored = readPasskey(address)
  return stored ? keccak256(bytesToHex(b64urlDecode(stored.credentialId))) : null
}

function translate(error: unknown): never {
  if (error instanceof BiometricError) throw error
  const name = error instanceof DOMException ? error.name : ''
  if (name === 'NotAllowedError' || name === 'AbortError') {
    throw new BiometricError(
      'CANCELLED',
      isInsideFrame()
        ? 'The biometric prompt was blocked or cancelled. Browsers often block it inside the Arc Studio preview, so open the app in its own browser tab.'
        : 'The biometric prompt was cancelled.',
    )
  }
  if (name === 'SecurityError') {
    throw new BiometricError('UNSUPPORTED', 'Passkeys are not allowed on this page. Open the app in its own browser tab over HTTPS.')
  }
  throw error
}

/**
 * Creates a Touch ID / Face ID platform passkey for this wallet address and stores its id locally.
 * Returns a fingerprint (keccak256 of the credential id). The per-escrow commitment is derived later,
 * when an escrow is created, so it can bind to that escrow's milestones.
 */
export async function registerBiometricPQKey(userAddress: Address): Promise<{ fingerprint: Hex; prf: boolean }> {
  if (!isPasskeySupported()) {
    throw new BiometricError('UNSUPPORTED', 'This browser does not support passkeys.')
  }
  try {
    const credential = (await navigator.credentials.create({
      publicKey: {
        rp: { name: 'ArcStreamVault', id: window.location.hostname },
        user: {
          id: Uint8Array.from(hexToBytes(keccak256(toHex(userAddress.toLowerCase())))),
          name: userAddress,
          displayName: `ArcStream ${userAddress.slice(0, 6)}...${userAddress.slice(-4)}`,
        },
        challenge: randomBytes(32),
        pubKeyCredParams: [
          { type: 'public-key', alg: -7 },
          { type: 'public-key', alg: -257 },
        ],
        authenticatorSelection: {
          authenticatorAttachment: 'platform',
          userVerification: 'required',
          residentKey: 'preferred',
        },
        attestation: 'none',
        timeout: 60_000,
        extensions: { prf: {} },
      },
    })) as PublicKeyCredential | null
    if (!credential) throw new BiometricError('CANCELLED', 'No passkey was created.')

    const prf = credential.getClientExtensionResults().prf?.enabled === true
    const stored: StoredPasskey = {
      credentialId: b64urlEncode(new Uint8Array(credential.rawId)),
      rpId: window.location.hostname,
      prf,
      fallbackMaster: prf ? undefined : bytesToHex(randomBytes(32)),
      createdAt: Date.now(),
    }
    localStorage.setItem(passkeyKey(userAddress), JSON.stringify(stored))
    notify()
    return { fingerprint: keccak256(bytesToHex(new Uint8Array(credential.rawId))), prf }
  } catch (error) {
    return translate(error)
  }
}

/** Prompts Touch ID / Face ID and returns the 32-byte master secret for this wallet's passkey. */
async function unlockMaster(userAddress: Address): Promise<Hex> {
  const stored = readPasskey(userAddress)
  if (!stored) {
    throw new BiometricError('NOT_REGISTERED', 'Set up your Touch ID / Face ID key first.')
  }
  try {
    const assertion = (await navigator.credentials.get({
      publicKey: {
        challenge: randomBytes(32),
        rpId: stored.rpId,
        allowCredentials: [{ type: 'public-key', id: b64urlDecode(stored.credentialId), transports: ['internal'] }],
        userVerification: 'required',
        timeout: 60_000,
        extensions: stored.prf ? { prf: { eval: { first: PRF_SALT } } } : undefined,
      },
    })) as PublicKeyCredential | null
    if (!assertion) throw new BiometricError('CANCELLED', 'The biometric prompt was dismissed.')

    if (stored.prf) {
      const first = assertion.getClientExtensionResults().prf?.results?.first
      if (!first) {
        throw new BiometricError(
          'PRF_UNAVAILABLE',
          'This browser did not return the passkey secret. Use the browser and device where you set up the key.',
        )
      }
      const bytes = first instanceof ArrayBuffer ? new Uint8Array(first) : new Uint8Array(first.buffer)
      return keccak256(bytesToHex(bytes))
    }
    if (!stored.fallbackMaster) {
      throw new BiometricError('NOT_REGISTERED', 'Set up your Touch ID / Face ID key again.')
    }
    return stored.fallbackMaster
  } catch (error) {
    return translate(error)
  }
}

function readRecords(address: string): Record<string, PqRecord> {
  try {
    const raw = localStorage.getItem(recordsKey(address))
    return raw ? (JSON.parse(raw) as Record<string, PqRecord>) : {}
  } catch {
    return {}
  }
}

export const hasRecordFor = (address: string, commitment: string): boolean =>
  !!readRecords(address)[commitment.toLowerCase()]

/**
 * Touch ID / Face ID prompt, then builds the Merkle root to pass as pqCommitment when creating an
 * escrow. The non-secret nonce and milestone count are saved so proofs can be rebuilt later.
 */
export async function createEscrowCommitment(
  userAddress: Address,
  vault: Address,
  chainId: number,
  milestoneCount: number,
): Promise<Hex> {
  const master = await unlockMaster(userAddress)
  const record: PqRecord = { nonce: bytesToHex(randomBytes(32)), milestoneCount, createdAt: Date.now() }
  const root = computeRoot({ master, record, chainId, vault, employer: userAddress })
  const records = readRecords(userAddress)
  records[root.toLowerCase()] = record
  localStorage.setItem(recordsKey(userAddress), JSON.stringify(records))
  return root
}

/**
 * Touch ID / Face ID prompt, then returns the pqProof bytes for one protected action.
 * action is the milestone index for a release, or the milestone count for a refund.
 */
export async function signWithBiometricPQKey(args: {
  userAddress: Address
  vault: Address
  chainId: number
  commitment: Hex
  action: number
}): Promise<Hex> {
  const record = readRecords(args.userAddress)[args.commitment.toLowerCase()]
  if (!record) {
    throw new BiometricError('NO_RECORD', 'This escrow was protected from a different browser or device, so its secrets are not here.')
  }
  const master = await unlockMaster(args.userAddress)
  const ctx: PqContext = {
    master,
    record,
    chainId: args.chainId,
    vault: args.vault,
    employer: args.userAddress,
  }
  if (computeRoot(ctx).toLowerCase() !== args.commitment.toLowerCase()) {
    throw new BiometricError('KEY_MISMATCH', 'This passkey does not match the one that protected this escrow.')
  }
  return buildProof(ctx, args.action)
}
