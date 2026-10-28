import type { Address } from 'viem'
import { arcTestnet } from 'viem/chains'

export { arcStreamVaultAbi } from './arcStreamVaultAbi'

/** Deployed ArcStreamVault address on Arc Testnet (chain 5042002). Leave undefined to show the "not deployed" state. */
export const VAULT_ADDRESS: Address | undefined = '0xbfeba9a6fe6b81f583417d426a3957d713f30965'

/** Deployment transaction, used to bound event log queries. */
export const DEPLOY_TX_HASH = '0x0d8a668fc76ac942d4436ef4c9314e5df46d95bbdc19bd84c60ec27a2d12d87a' as const

/** Official ERC-20 USDC on Arc Testnet (6 decimals). It is also the chain's gas token; this app uses the ERC-20 view only. */
export const USDC_ADDRESS: Address = '0x3600000000000000000000000000000000000000'

const explorerBase = arcTestnet.blockExplorers.default.url

export const txUrl = (hash: string) => `${explorerBase}/tx/${hash}`
export const addressUrl = (address: string) => `${explorerBase}/address/${address}`

export const FAUCET_URL = 'https://faucet.circle.com'
