import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { getAbiItem, type Address, type Hex } from 'viem'
import { ARC_CHAIN_ID } from '@/config'
import { DEPLOY_TX_HASH, VAULT_ADDRESS, arcStreamVaultAbi } from '@/contracts/vault'

const releasedEvent = getAbiItem({ abi: arcStreamVaultAbi, name: 'MilestoneReleased' })
const uncontestedEvent = getAbiItem({ abi: arcStreamVaultAbi, name: 'UncontestedMilestoneClaimed' })

export interface SettlementRecord {
  txHash: Hex
  /** Unix seconds of the block that settled the milestone, or null if the block could not be read. */
  timestamp: number | null
  /** The wallet that was actually paid, taken from the event. */
  payee: Address
  amount: bigint
  /** release: employer or contractor released an approved milestone. uncontested: contractor claimed after the review window. */
  kind: 'release' | 'uncontested'
}

/**
 * Finds the onchain event that paid a milestone, for invoices and receipts. Resolves to null when no
 * matching event is found (for example if the node limits the log range).
 */
export function useSettlement(escrowId: bigint, milestoneIndex: number, enabled: boolean) {
  const client = usePublicClient({ chainId: ARC_CHAIN_ID })

  return useQuery({
    queryKey: ['settlement', VAULT_ADDRESS, escrowId.toString(), milestoneIndex],
    enabled: enabled && !!client && !!VAULT_ADDRESS && !!DEPLOY_TX_HASH,
    staleTime: Infinity,
    retry: 1,
    queryFn: async (): Promise<SettlementRecord | null> => {
      if (!client || !VAULT_ADDRESS || !DEPLOY_TX_HASH) return null
      const { blockNumber: fromBlock } = await client.getTransactionReceipt({ hash: DEPLOY_TX_HASH })
      const [released, uncontested] = await Promise.all([
        client.getLogs({ address: VAULT_ADDRESS, event: releasedEvent, args: { escrowId }, fromBlock, toBlock: 'latest' }),
        client.getLogs({ address: VAULT_ADDRESS, event: uncontestedEvent, args: { escrowId }, fromBlock, toBlock: 'latest' }),
      ])
      const releasedMatch = released.find((log) => Number(log.args.milestoneIndex) === milestoneIndex)
      const uncontestedMatch = uncontested.find((log) => Number(log.args.milestoneIndex) === milestoneIndex)
      const match = releasedMatch ?? uncontestedMatch
      if (!match || !match.args.contractor || match.args.amount === undefined) return null
      const block = await client.getBlock({ blockNumber: match.blockNumber }).catch(() => null)
      return {
        txHash: match.transactionHash,
        timestamp: block ? Number(block.timestamp) : null,
        payee: match.args.contractor,
        amount: match.args.amount,
        kind: releasedMatch ? 'release' : 'uncontested',
      }
    },
  })
}
