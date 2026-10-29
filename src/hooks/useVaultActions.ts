import { useAccount, usePublicClient, useWriteContract } from 'wagmi'
import { erc20Abi, type Address, type Hex } from 'viem'
import { ARC_CHAIN_ID } from '@/config'
import { USDC_ADDRESS, VAULT_ADDRESS, arcStreamVaultAbi } from '@/contracts/vault'
import { useTx } from '@/components/txContext'

export function useVaultActions() {
  const { address } = useAccount()
  const publicClient = usePublicClient({ chainId: ARC_CHAIN_ID })
  const { writeContractAsync } = useWriteContract()
  const { runFlow } = useTx()

  const requireVault = (): Address => {
    if (!VAULT_ADDRESS) throw new Error('ArcStreamVault is not deployed yet')
    return VAULT_ADDRESS
  }

  /** Step 1: USDC approve (skipped if allowance already covers it). Step 2: createEscrow. */
  const createEscrow = (
    contractor: Address,
    amounts: bigint[],
    descriptions: string[],
    pqPublicKey: Hex = '0x',
    inspectionPeriod = 0,
  ) => {
    const vault = requireVault()
    const total = amounts.reduce((sum, a) => sum + a, 0n)
    return runFlow('Create escrow', [
      {
        label: 'Approve USDC allowance',
        skipIf: async () => {
          if (!publicClient || !address) return false
          const allowance = await publicClient.readContract({
            address: USDC_ADDRESS,
            abi: erc20Abi,
            functionName: 'allowance',
            args: [address, vault],
          })
          return allowance >= total
        },
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: USDC_ADDRESS,
            abi: erc20Abi,
            functionName: 'approve',
            args: [vault, total],
          }),
      },
      {
        label: 'Fund escrow and create milestones',
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: vault,
            abi: arcStreamVaultAbi,
            functionName: 'createEscrow',
            args: [contractor, amounts, descriptions, pqPublicKey, BigInt(inspectionPeriod)],
          }),
      },
    ])
  }

  const approveMilestone = (escrowId: bigint, index: number) =>
    runFlow('Approve milestone', [
      {
        label: `Approve milestone ${index + 1}`,
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'approveMilestone',
            args: [escrowId, BigInt(index)],
          }),
      },
    ])

  /** pqProof (SLH-DSA signature) is only checked when the employer releases a protected escrow; contractors pass 0x. */
  const releaseMilestone = (escrowId: bigint, index: number, pqProof: Hex = '0x') =>
    runFlow('Claim payout', [
      {
        label: `Release milestone ${index + 1} to contractor`,
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'releaseMilestone',
            args: [escrowId, BigInt(index), pqProof],
          }),
      },
    ])

  /** Employer shortcut: approve a submitted milestone, then release it, as two confirmations in one flow. */
  const approveAndRelease = (escrowId: bigint, index: number, pqProof: Hex = '0x') =>
    runFlow('Approve and release payout', [
      {
        label: `Approve milestone ${index + 1}`,
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'approveMilestone',
            args: [escrowId, BigInt(index)],
          }),
      },
      {
        label: `Release milestone ${index + 1} to contractor`,
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'releaseMilestone',
            args: [escrowId, BigInt(index), pqProof],
          }),
      },
    ])

  const submitWork = (escrowId: bigint, index: number, proof: string) =>
    runFlow('Submit work', [
      {
        label: `Submit proof for milestone ${index + 1}`,
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'submitMilestoneWork',
            args: [escrowId, BigInt(index), proof],
          }),
      },
    ])

  /** Contractor claims an unapproved milestone after the employer's review window has passed. */
  const claimUncontested = (escrowId: bigint, index: number) =>
    runFlow('Claim payout after review window', [
      {
        label: `Claim milestone ${index + 1}`,
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'claimUncontestedMilestone',
            args: [escrowId, BigInt(index)],
          }),
      },
    ])

  const refundRemaining = (escrowId: bigint, pqProof: Hex = '0x') =>
    runFlow('Refund unapproved milestones', [
      {
        label: 'Refund unapproved funds to employer',
        send: () =>
          writeContractAsync({
            chainId: ARC_CHAIN_ID,
            address: requireVault(),
            abi: arcStreamVaultAbi,
            functionName: 'refundRemaining',
            args: [escrowId, pqProof],
          }),
      },
    ])

  return {
    createEscrow,
    approveMilestone,
    releaseMilestone,
    approveAndRelease,
    submitWork,
    claimUncontested,
    refundRemaining,
  }
}
