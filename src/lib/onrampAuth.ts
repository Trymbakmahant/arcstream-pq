import { keccak256, toHex } from 'viem'

/** Header that carries the wallet-ownership proof from the browser to the onramp session route. */
export const ONRAMP_AUTH_HEADER = 'x-onramp-auth'

/** How long a signed proof stays valid, in milliseconds. */
export const ONRAMP_AUTH_MAX_AGE_MS = 120_000

/** The widget is scoped to USDC on Arc; the server only mints sessions with exactly this scope. */
export const ONRAMP_ASSETS = { tokens: ['USDC'], chains: ['arc'] }

export interface OnrampAuthProof {
  address: string
  issuedAt: string
  signature: string
}

/** Text the wallet signs. It proves control of the address and moves no funds. */
export function onrampAuthMessage(address: string, issuedAt: string): string {
  return [
    'ArcStream-PQ card purchase',
    `Wallet: ${address.toLowerCase()}`,
    `Issued: ${issuedAt}`,
    'Signing proves you control this wallet. It does not move funds or give any approval.',
  ].join('\n')
}

/** Stable opaque id for Circle (a hash of the wallet address, not the address itself). */
export function onrampAppUserId(address: string): string {
  return `arcstream-${keccak256(toHex(address.toLowerCase())).slice(2, 34)}`
}
