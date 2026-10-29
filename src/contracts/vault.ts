import type { Address } from 'viem'
import { arcTestnet } from 'viem/chains'

export { arcStreamVaultAbi } from './arcStreamVaultAbi'

/** Deployed ArcStreamVault address on Arc Testnet (chain 5042002). Leave undefined to show the "not deployed" state. */
export const VAULT_ADDRESS: Address | undefined = '0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53'

/** Deployment transaction, used to bound event log queries. */
export const DEPLOY_TX_HASH = '0x87239976031b6b7fc60da6105e9679e7b5f2c669fe654871b0f16136f3d6118f' as const

/** Official ERC-20 USDC on Arc Testnet (6 decimals). It is also the chain's gas token; this app uses the ERC-20 view only. */
export const USDC_ADDRESS: Address = '0x3600000000000000000000000000000000000000'

const explorerBase = arcTestnet.blockExplorers.default.url

export const txUrl = (hash: string) => `${explorerBase}/tx/${hash}`
export const addressUrl = (address: string) => `${explorerBase}/address/${address}`

export const FAUCET_URL = 'https://faucet.circle.com'
