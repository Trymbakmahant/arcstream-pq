import type { Address, Hex } from 'viem'
import { arc, arcTestnet } from 'viem/chains'
import { MAINNET_DEPLOY_TX, MAINNET_VAULT_ADDRESS } from '@/contracts/mainnet'

export type NetworkId = 'testnet' | 'mainnet'

export interface NetworkInfo {
  id: NetworkId
  /** Short name used in the UI, e.g. "Arc Testnet". */
  label: string
  chainId: 5042 | 5042002
  rpcUrl: string
  explorerUrl: string
  /** ERC-20 interface of native USDC (6 decimals). */
  usdc: Address
  /** Deployed ArcStreamVault, or undefined when it has not been deployed on this network yet. */
  vault: Address | undefined
  /** Deployment transaction, used to bound event log queries. */
  deployTx: Hex | undefined
  isMainnet: boolean
}

const USDC: Address = '0x3600000000000000000000000000000000000000'

export const NETWORKS: Record<NetworkId, NetworkInfo> = {
  testnet: {
    id: 'testnet',
    label: 'Arc Testnet',
    chainId: arcTestnet.id,
    rpcUrl: arcTestnet.rpcUrls.default.http[0],
    explorerUrl: arcTestnet.blockExplorers.default.url,
    usdc: USDC,
    vault: '0x464504fe41fef085413c52cfc6fdbeb15637c0fd',
    deployTx: '0x571bc7bad262af6a98ee95352d9a43734c14286676fde496141017254657cfce',
    isMainnet: false,
  },
  mainnet: {
    id: 'mainnet',
    label: 'Arc Mainnet',
    chainId: arc.id,
    rpcUrl: arc.rpcUrls.default.http[0],
    explorerUrl: arc.blockExplorers.default.url,
    usdc: USDC,
    vault: MAINNET_VAULT_ADDRESS,
    deployTx: MAINNET_DEPLOY_TX,
    isMainnet: true,
  },
}

const STORAGE_KEY = 'arcstream.network'

function readStored(): NetworkId {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'mainnet' ? 'mainnet' : 'testnet'
  } catch {
    return 'testnet'
  }
}

/** The network this page load runs on. Switching reloads the app, so every module sees a single fixed value. */
export const NETWORK: NetworkInfo = NETWORKS[readStored()]

export function switchNetwork(id: NetworkId): void {
  if (id === NETWORK.id) return
  try {
    localStorage.setItem(STORAGE_KEY, id)
  } catch {
    // Storage can be unavailable (private mode); the switch simply will not persist.
  }
  window.location.reload()
}
