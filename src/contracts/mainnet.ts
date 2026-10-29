import type { Address, Hex } from 'viem'

/**
 * Arc Mainnet reference values, from the official Arc docs
 * (docs.arc.io/arc/references/connect-to-arc and /contract-addresses). Not used by the running app,
 * which targets Arc Testnet. Review every value yourself before relying on it.
 */
export const ARC_MAINNET = {
  chainId: 5042,
  rpcUrl: 'https://rpc.mainnet.arc.io',
  explorerUrl: 'https://explorer.arc.io',
  /** ERC-20 interface of native USDC (6 decimals). */
  usdc: '0x3600000000000000000000000000000000000000' as Address,
  /** Arc's native PQ Signature Verify precompile (SLH-DSA-SHA2-128s). */
  pqPrecompile: '0x1800000000000000000000000000000000000004' as Address,
} as const

/**
 * Fill these in only after YOU deploy ArcStreamVault to Arc Mainnet from your own wallet
 * (see docs/mainnet-deploy.md). Arc Studio does not deploy to mainnet.
 */
export const MAINNET_VAULT_ADDRESS: Address | undefined = undefined
export const MAINNET_DEPLOY_TX: Hex | undefined = undefined
