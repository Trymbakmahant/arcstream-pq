import { concat, encodeAbiParameters, keccak256, toHex, type Address, type Hex } from 'viem'

/**
 * Post-quantum signing for employer release and refund.
 *
 * The contract verifies an SLH-DSA-SHA2-128s (FIPS 205) signature through Arc's native PQ Signature Verify
 * precompile. The 32-byte public key is committed when the escrow is created. The signing key is derived
 * in memory from the 32-byte master secret that Touch ID / Face ID unlocks (see lib/webauthn.ts), and is
 * never stored. Signing runs in a Web Worker because SLH-DSA-SHA2-128s takes a few seconds in JavaScript.
 */

export const PQ_PUBLIC_KEY_LENGTH = 32
export const PQ_SIGNATURE_LENGTH = 7856

/** Must match PQ_DOMAIN in ArcStreamVault.sol. */
export const PQ_DOMAIN = keccak256(toHex('ArcStreamVault.PQ.v1'))

/** Must match ArcStreamVault.pqSigningMessage(escrowId, action): the 32-byte message the precompile verifies. */
export function signingMessage(args: { chainId: number; vault: Address; escrowId: bigint; action: number }): Hex {
  return keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'uint256' }, { type: 'address' }, { type: 'uint256' }, { type: 'uint256' }],
      [PQ_DOMAIN, BigInt(args.chainId), args.vault, args.escrowId, BigInt(args.action)],
    ),
  )
}

/** 48-byte SLH-DSA-SHA2-128s seed (sk_seed || sk_prf || pk_seed) expanded from the 32-byte master secret. */
export function seedFromMaster(master: Hex): Hex {
  const a = keccak256(concat([toHex('arcstream-slh-dsa-seed/v1'), master, '0x01']))
  const b = keccak256(concat([toHex('arcstream-slh-dsa-seed/v1'), master, '0x02']))
  return concat([a, `0x${b.slice(2, 34)}`])
}

interface WorkerRequest {
  id: number
  op: 'derive' | 'sign'
  seed: Hex
  message?: Hex
}

export interface WorkerResult {
  publicKey: Hex
  signature?: Hex
}

type WorkerReply = { id: number; ok: true; result: WorkerResult } | { id: number; ok: false; error: string }

let worker: Worker | null = null
let nextId = 1
const pending = new Map<number, { resolve: (value: WorkerResult) => void; reject: (reason: Error) => void }>()

function getWorker(): Worker {
  if (worker) return worker
  worker = new Worker(new URL('./pq.worker.ts', import.meta.url), { type: 'module' })
  worker.onmessage = (event: MessageEvent<WorkerReply>) => {
    const entry = pending.get(event.data.id)
    if (!entry) return
    pending.delete(event.data.id)
    if (event.data.ok) entry.resolve(event.data.result)
    else entry.reject(new Error(event.data.error))
  }
  worker.onerror = () => {
    for (const [, entry] of pending) entry.reject(new Error('The post-quantum signing worker failed to load.'))
    pending.clear()
    worker = null
  }
  return worker
}

function run(request: Omit<WorkerRequest, 'id'>): Promise<WorkerResult> {
  return new Promise((resolve, reject) => {
    const id = nextId++
    pending.set(id, { resolve, reject })
    getWorker().postMessage({ ...request, id } satisfies WorkerRequest)
  })
}

/** Public key (32 bytes) for the master secret. Pass this as pqPublicKey when creating an escrow. */
export async function derivePublicKey(master: Hex): Promise<Hex> {
  return (await run({ op: 'derive', seed: seedFromMaster(master) })).publicKey
}

/** Signs a 32-byte message. Returns the 7,856-byte signature and the public key it was made with. */
export async function signDigest(master: Hex, message: Hex): Promise<{ signature: Hex; publicKey: Hex }> {
  const result = await run({ op: 'sign', seed: seedFromMaster(master), message })
  if (!result.signature) throw new Error('The signing worker returned no signature.')
  return { signature: result.signature, publicKey: result.publicKey }
}

/** Short display form of a 32-byte hash, e.g. 0x4f8e...12a9. */
export const fingerprint = (hash: string) => `${hash.slice(0, 6)}...${hash.slice(-4)}`
