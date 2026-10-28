/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { arcTestnet } from 'viem/chains'
import { injected } from 'wagmi/connectors'
import { registerChain } from './tracing'

export const ARC_CHAIN_ID = arcTestnet.id
const rpcUrl = arcTestnet.rpcUrls.default.http[0]

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(ARC_CHAIN_ID, rpcUrl)

export const config = createConfig({
  chains: [arcTestnet],
  connectors: [injected()],
  transports: {
    [arcTestnet.id]: http(rpcUrl),
  },
})
