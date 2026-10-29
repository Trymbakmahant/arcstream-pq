import { NETWORK } from '@/lib/network'

export { arcStreamVaultAbi } from './arcStreamVaultAbi'

/** Deployed ArcStreamVault on the selected network. Undefined shows the "not deployed" state. */
export const VAULT_ADDRESS = NETWORK.vault

/** Deployment transaction on the selected network, used to bound event log queries. */
export const DEPLOY_TX_HASH = NETWORK.deployTx

/** Official ERC-20 USDC (6 decimals). It is also the chain's gas token; this app uses the ERC-20 view only. */
export const USDC_ADDRESS = NETWORK.usdc

const explorerBase = NETWORK.explorerUrl

export const txUrl = (hash: string) => `${explorerBase}/tx/${hash}`
export const addressUrl = (address: string) => `${explorerBase}/address/${address}`

export const FAUCET_URL = 'https://faucet.circle.com'
