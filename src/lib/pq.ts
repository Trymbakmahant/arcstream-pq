import { concat, encodeAbiParameters, encodePacked, keccak256, zeroHash, type Address, type Hex } from 'viem'

/**
 * Hash-based one-time-secret second factor, matching ArcStreamVault._verifyQuantumProof.
 *
 * Every protected escrow commits to a Merkle root. Leaf `action` (a milestone index for release,
 * milestoneCount for refund) is keccak256(keccak256(abi.encode(chainid, vault, employer, action, secret))).
 * A secret is revealed only in the transaction that uses it, so each one is single-use.
 */

export const PQ_MAX_DEPTH = 8

export interface PqRecord {
  nonce: Hex
  milestoneCount: number
  createdAt: number
}

export interface PqContext {
  master: Hex
  record: PqRecord
  chainId: number
  vault: Address
  employer: Address
}

const sortedHash = (a: Hex, b: Hex): Hex =>
  BigInt(a) <= BigInt(b) ? keccak256(concat([a, b])) : keccak256(concat([b, a]))

export function deriveSecret(master: Hex, nonce: Hex, action: number): Hex {
  return keccak256(encodePacked(['bytes32', 'bytes32', 'uint256'], [master, nonce, BigInt(action)]))
}

export function leafFor(ctx: Omit<PqContext, 'record' | 'master'>, action: number, secret: Hex): Hex {
  const inner = keccak256(
    encodeAbiParameters(
      [{ type: 'uint256' }, { type: 'address' }, { type: 'address' }, { type: 'uint256' }, { type: 'bytes32' }],
      [BigInt(ctx.chainId), ctx.vault, ctx.employer, BigInt(action), secret],
    ),
  )
  return keccak256(inner)
}

/** One leaf per milestone plus one for refund, padded with zero hashes to a power of two. */
function buildLayers(ctx: PqContext): Hex[][] {
  const actions = ctx.record.milestoneCount + 1
  const leaves: Hex[] = []
  for (let action = 0; action < actions; action++) {
    leaves.push(leafFor(ctx, action, deriveSecret(ctx.master, ctx.record.nonce, action)))
  }
  let size = 1
  while (size < leaves.length) size *= 2
  while (leaves.length < size) leaves.push(zeroHash)

  const layers: Hex[][] = [leaves]
  while (layers[layers.length - 1].length > 1) {
    const prev = layers[layers.length - 1]
    const next: Hex[] = []
    for (let i = 0; i < prev.length; i += 2) next.push(sortedHash(prev[i], prev[i + 1]))
    layers.push(next)
  }
  if (layers.length - 1 > PQ_MAX_DEPTH) throw new Error('Too many milestones for a protected escrow')
  return layers
}

export function computeRoot(ctx: PqContext): Hex {
  const layers = buildLayers(ctx)
  return layers[layers.length - 1][0]
}

/** abi.encode(bytes32 secret, bytes32[] path), the format the contract expects. */
export function buildProof(ctx: PqContext, action: number): Hex {
  const layers = buildLayers(ctx)
  const path: Hex[] = []
  let index = action
  for (let level = 0; level < layers.length - 1; level++) {
    path.push(layers[level][index ^ 1])
    index = Math.floor(index / 2)
  }
  const secret = deriveSecret(ctx.master, ctx.record.nonce, action)
  return encodeAbiParameters([{ type: 'bytes32' }, { type: 'bytes32[]' }], [secret, path])
}

/** Short display form such as 0x4f8e...12a9. */
export const fingerprint = (value: string) => `${value.slice(0, 6)}...${value.slice(-4)}`
