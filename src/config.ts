/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { arc, arcTestnet } from 'viem/chains'
import { injected } from 'wagmi/connectors'
import { NETWORK, NETWORKS } from '@/lib/network'
import { registerChain } from './tracing'

/** Chain id of the network selected in the app (Arc Testnet by default). */
export const ARC_CHAIN_ID = NETWORK.chainId

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(NETWORKS.testnet.chainId, NETWORKS.testnet.rpcUrl)
registerChain(NETWORKS.mainnet.chainId, NETWORKS.mainnet.rpcUrl)

export const config = createConfig({
  chains: [arcTestnet, arc],
  connectors: [injected()],
  transports: {
    [arcTestnet.id]: http(NETWORKS.testnet.rpcUrl),
    [arc.id]: http(NETWORKS.mainnet.rpcUrl),
  },
})
