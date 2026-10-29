import { bytesToHex, hexToBytes, keccak256, toHex, type Address, type Hex } from 'viem'
import { derivePublicKey, signDigest, signingMessage } from '@/lib/pq'

/**
 * Touch ID / Face ID (WebAuthn passkey) as the unlock for the post-quantum signing key.
 *
 * What this is: the passkey (a P-256 platform credential) proves a person is present and verified on
 * this device. When the browser supports the WebAuthn PRF extension, the passkey also derives a stable
 * 32-byte master secret, so nothing secret is stored. The SLH-DSA-SHA2-128s signing key is derived from
 * that master secret in memory each time and discarded (see lib/pq.ts). Without PRF, a random master
 * secret is kept in localStorage and the biometric prompt only gates access to it.
 *
 * What it is not: the passkey's own P-256 signature is never sent onchain and is not post-quantum. The
 * onchain check is the SLH-DSA signature, verified by Arc's native PQ Signature Verify precompile.
 */

export type BiometricErrorCode =
  | 'UNSUPPORTED'
  | 'NOT_REGISTERED'
  | 'CANCELLED'
  | 'PRF_UNAVAILABLE'
  | 'KEY_MISMATCH'
  | 'SIGNING_FAILED'

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
 * Returns a fingerprint (keccak256 of the credential id). The post-quantum public key is derived later,
 * when an escrow is created.
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

/**
 * Touch ID / Face ID prompt, then derives the 32-byte SLH-DSA-SHA2-128s public key to pass as
 * pqPublicKey when creating an escrow. The same passkey always yields the same key.
 */
export async function createPqPublicKey(userAddress: Address): Promise<Hex> {
  const master = await unlockMaster(userAddress)
  try {
    return await derivePublicKey(master)
  } catch (error) {
    throw new BiometricError('SIGNING_FAILED', error instanceof Error ? error.message : 'Could not derive the post-quantum key.')
  }
}

/**
 * Touch ID / Face ID prompt, then signs one protected action with the derived post-quantum key and
 * returns the 7,856-byte signature to pass as pqProof. action is the milestone index for a release, or
 * the milestone count for a refund. publicKey is the key stored in the escrow; the derived key must match it.
 */
export async function signWithBiometricPQKey(args: {
  userAddress: Address
  vault: Address
  chainId: number
  escrowId: bigint
  action: number
  publicKey: Hex
}): Promise<Hex> {
  const master = await unlockMaster(args.userAddress)
  const message = signingMessage({
    chainId: args.chainId,
    vault: args.vault,
    escrowId: args.escrowId,
    action: args.action,
  })
  try {
    const { signature, publicKey } = await signDigest(master, message)
    if (publicKey.toLowerCase() !== args.publicKey.toLowerCase()) {
      throw new BiometricError('KEY_MISMATCH', 'This passkey does not match the one that protected this escrow.')
    }
    return signature
  } catch (error) {
    if (error instanceof BiometricError) throw error
    throw new BiometricError('SIGNING_FAILED', error instanceof Error ? error.message : 'Post-quantum signing failed.')
  }
}
