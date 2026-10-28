import { BaseError, ContractFunctionRevertedError } from 'viem'

const CUSTOM_ERROR_COPY: Record<string, string> = {
  Unauthorized: 'Your wallet is not allowed to do this on this escrow.',
  InvalidContractor: 'Contractor address is invalid. It cannot be empty or your own wallet.',
  InvalidMilestoneCount: 'An escrow needs between 1 and 50 milestones.',
  InvalidAmount: 'Every milestone needs an amount greater than zero.',
  EscrowNotFound: 'That escrow does not exist.',
  MilestoneOutOfRange: 'That milestone does not exist.',
  EscrowTerminated: 'This escrow has already been closed.',
  MilestoneAlreadyApproved: 'This milestone is already approved.',
  MilestoneAlreadyReleased: 'This milestone has already been paid out.',
  MilestoneNotApproved: 'The employer has not approved this milestone yet.',
  NothingToRefund: 'There is nothing to refund right now.',
  UnexpectedTokenReceipt: 'The vault did not receive the exact USDC amount.',
  EmptyWorkProof: 'Paste a proof link or hash before submitting.',
  WorkProofTooLong: 'Proof must be 256 characters or fewer.',
  WorkNotSubmitted: 'The contractor has not submitted work for this milestone yet.',
  WorkAlreadySubmitted: 'Submitted work is waiting for your approval, so a refund is blocked.',
  EscrowSettled: 'This escrow was settled by mutual cancellation.',
}

export function isUserRejection(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : ''
  const code = (error as { code?: number } | null)?.code
  return code === 4001 || message.includes('user rejected') || message.includes('user denied')
}

export function parseOnchainError(error: unknown): string {
  if (isUserRejection(error)) return 'Transaction cancelled.'

  if (error instanceof BaseError) {
    const reverted = error.walk((e) => e instanceof ContractFunctionRevertedError)
    if (reverted instanceof ContractFunctionRevertedError) {
      const name = reverted.data?.errorName
      if (name && CUSTOM_ERROR_COPY[name]) return CUSTOM_ERROR_COPY[name]
    }
  }

  const message = error instanceof Error ? error.message : ''
  for (const [name, copy] of Object.entries(CUSTOM_ERROR_COPY)) {
    if (message.includes(name)) return copy
  }

  const lower = message.toLowerCase()
  if (lower.includes('insufficient funds') || lower.includes('exceeds balance')) {
    return 'Insufficient balance. Add testnet USDC and try again.'
  }
  if (lower.includes('allowance')) return 'USDC allowance is too low. Approve the amount first.'
  if (lower.includes('network') || lower.includes('timeout')) {
    return 'Network issue. Check your connection and retry.'
  }
  if (lower.includes('reverted')) return 'The transaction was rejected by the contract.'
  return 'Something went wrong. Please try again.'
}
