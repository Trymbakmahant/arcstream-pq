import { useQuery } from '@tanstack/react-query'
import { useAccount, usePublicClient } from 'wagmi'
import type { Address, Hex } from 'viem'
import { ARC_CHAIN_ID } from '@/config'
import { VAULT_ADDRESS, arcStreamVaultAbi } from '@/contracts/vault'

export interface MilestoneView {
  amount: bigint
  description: string
  isApproved: boolean
  isReleased: boolean
  workProofHash: string
  isWorkSubmitted: boolean
}

export interface EscrowView {
  id: bigint
  employer: Address
  contractor: Address
  totalDeposited: bigint
  totalReleased: bigint
  milestoneCount: number
  isTerminated: boolean
  isSettled: boolean
  pqCommitment: Hex
  isPQProtected: boolean
  milestones: MilestoneView[]
}

export type MilestoneStatus = 'PENDING' | 'WORK SUBMITTED' | 'APPROVED' | 'RELEASED' | 'CLOSED'

export function milestoneStatus(escrow: EscrowView, milestone: MilestoneView): MilestoneStatus {
  if (milestone.isReleased) return 'RELEASED'
  if (milestone.isApproved && !escrow.isSettled) return 'APPROVED'
  if (escrow.isTerminated) return 'CLOSED'
  if (milestone.isWorkSubmitted) return 'WORK SUBMITTED'
  return 'PENDING'
}

const sameAddress = (a: string, b?: string) => !!b && a.toLowerCase() === b.toLowerCase()

export function useEscrows() {
  const { address } = useAccount()
  const client = usePublicClient({ chainId: ARC_CHAIN_ID })

  const query = useQuery({
    queryKey: ['escrows', address, VAULT_ADDRESS],
    enabled: !!address && !!client && !!VAULT_ADDRESS,
    refetchInterval: 8000,
    queryFn: async (): Promise<EscrowView[]> => {
      if (!client || !address || !VAULT_ADDRESS) return []
      const ids = await client.readContract({
        address: VAULT_ADDRESS,
        abi: arcStreamVaultAbi,
        functionName: 'getUserEscrows',
        args: [address],
      })

      const escrows = await Promise.all(
        ids.map(async (id): Promise<EscrowView> => {
          const [agreement, milestones, isSettled] = await Promise.all([
            client.readContract({
              address: VAULT_ADDRESS!,
              abi: arcStreamVaultAbi,
              functionName: 'getEscrow',
              args: [id],
            }),
            client.readContract({
              address: VAULT_ADDRESS!,
              abi: arcStreamVaultAbi,
              functionName: 'getMilestones',
              args: [id],
            }),
            client.readContract({
              address: VAULT_ADDRESS!,
              abi: arcStreamVaultAbi,
              functionName: 'isSettled',
              args: [id],
            }),
          ])
          return {
            id,
            employer: agreement.employer,
            contractor: agreement.contractor,
            totalDeposited: agreement.totalDeposited,
            totalReleased: agreement.totalReleased,
            milestoneCount: Number(agreement.milestoneCount),
            isTerminated: agreement.isTerminated,
            isSettled,
            pqCommitment: agreement.pqCommitment,
            isPQProtected: agreement.isPQProtected,
            milestones: milestones.map((m) => ({
              amount: m.amount,
              description: m.description,
              isApproved: m.isApproved,
              isReleased: m.isReleased,
              workProofHash: m.workProofHash,
              isWorkSubmitted: m.isWorkSubmitted,
            })),
          }
        }),
      )
      return escrows.sort((a, b) => (a.id < b.id ? 1 : -1))
    },
  })

  const all = query.data ?? []
  return {
    ...query,
    asEmployer: all.filter((e) => sameAddress(e.employer, address)),
    asContractor: all.filter((e) => sameAddress(e.contractor, address)),
  }
}
