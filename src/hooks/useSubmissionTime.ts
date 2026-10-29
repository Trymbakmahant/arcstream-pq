import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { getAbiItem } from 'viem'
import { ARC_CHAIN_ID } from '@/config'
import { DEPLOY_TX_HASH, VAULT_ADDRESS, arcStreamVaultAbi } from '@/contracts/vault'

const workSubmittedEvent = getAbiItem({ abi: arcStreamVaultAbi, name: 'WorkSubmitted' })

/**
 * Looks up when the latest proof for a milestone was submitted, from the WorkSubmitted event.
 * The contract does not store timestamps, so this reads logs and the block time.
 * Resolves to a unix timestamp in seconds, or null if no matching event is found.
 */
export function useSubmissionTime(escrowId: bigint, milestoneIndex: number, proof: string, enabled: boolean) {
  const client = usePublicClient({ chainId: ARC_CHAIN_ID })

  return useQuery({
    queryKey: ['submission-time', escrowId.toString(), milestoneIndex, proof],
    enabled: enabled && !!client && !!VAULT_ADDRESS,
    staleTime: Infinity,
    retry: 1,
    queryFn: async (): Promise<number | null> => {
      if (!client || !VAULT_ADDRESS || !DEPLOY_TX_HASH) return null
      const deployReceipt = await client.getTransactionReceipt({ hash: DEPLOY_TX_HASH })
      const logs = await client.getLogs({
        address: VAULT_ADDRESS,
        event: workSubmittedEvent,
        args: { escrowId },
        fromBlock: deployReceipt.blockNumber,
        toBlock: 'latest',
      })
      const matches = logs.filter((log) => Number(log.args.milestoneIndex) === milestoneIndex)
      const latest = matches[matches.length - 1]
      if (!latest) return null
      const block = await client.getBlock({ blockNumber: latest.blockNumber })
      return Number(block.timestamp)
    },
  })
}
