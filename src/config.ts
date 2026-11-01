/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, fallback, createConfig } from 'wagmi'
import { arc, arcTestnet } from 'viem/chains'
import { injected } from 'wagmi/connectors'
import { NETWORK, NETWORKS } from '@/lib/network'
import { registerChain } from './tracing'

/** Chain id of the network selected in the app (Arc Testnet by default). */
export const ARC_CHAIN_ID = NETWORK.chainId

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(NETWORKS.testnet.chainId, NETWORKS.testnet.rpcUrl)
registerChain(NETWORKS.mainnet.chainId, NETWORKS.mainnet.rpcUrl)

const testnetHttp = typeof window !== 'undefined' ? http('/rpc-testnet') : http(NETWORKS.testnet.rpcUrl)
const mainnetHttp = typeof window !== 'undefined' ? http('/rpc-mainnet') : http(NETWORKS.mainnet.rpcUrl)

export const config = createConfig({
  chains: [arcTestnet, arc],
  connectors: [injected()],
  transports: {
    [arcTestnet.id]: fallback([
      testnetHttp,
      http(NETWORKS.testnet.rpcUrl),
      http('https://rpc.drpc.testnet.arc.io'),
      http('https://rpc.quicknode.testnet.arc.io'),
      http('https://rpc.blockdaemon.testnet.arc.io'),
    ]),
    [arc.id]: fallback([
      mainnetHttp,
      http(NETWORKS.mainnet.rpcUrl),
      http('https://rpc.drpc.arc.io'),
      http('https://rpc.quicknode.arc.io'),
    ]),
  },
})
