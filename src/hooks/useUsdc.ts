import { useQuery } from '@tanstack/react-query'
import { useAccount, usePublicClient } from 'wagmi'
import { erc20Abi } from 'viem'
import { ARC_CHAIN_ID } from '@/config'
import { USDC_ADDRESS } from '@/contracts/vault'

/** Single USDC balance from the ERC-20 view (6 decimals). On Arc this is the same pool as gas. */
export function useUsdcBalance() {
  const { address } = useAccount()
  const client = usePublicClient({ chainId: ARC_CHAIN_ID })

  return useQuery({
    queryKey: ['usdc-balance', address],
    enabled: !!address && !!client,
    refetchInterval: 10000,
    queryFn: async () => {
      if (!client || !address) return 0n
      return client.readContract({
        address: USDC_ADDRESS,
        abi: erc20Abi,
        functionName: 'balanceOf',
        args: [address],
      })
    },
  })
}
