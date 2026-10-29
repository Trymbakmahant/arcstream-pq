import type { EscrowView, MilestoneView } from '@/hooks/useEscrows'

export const DAY_SECONDS = 86_400

/** Review window choices offered when creating an escrow (the contract allows 1 to 30 days). */
export const REVIEW_WINDOW_DAYS = [1, 3, 7, 14, 30] as const
export const DEFAULT_REVIEW_DAYS = 7

/** Unix time (seconds) after which the contractor may claim unapproved, submitted work. Null when not applicable. */
export function claimableAt(escrow: EscrowView, milestone: MilestoneView): number | null {
  if (escrow.isTerminated || milestone.isReleased || milestone.isApproved || !milestone.isWorkSubmitted) return null
  if (milestone.submittedAt === 0) return null
  return milestone.submittedAt + escrow.inspectionPeriod
}

/** Short human duration such as "6d 4h", "5h 12m" or "under 1m". */
export function formatDuration(seconds: number): string {
  if (seconds < 60) return 'under 1m'
  const days = Math.floor(seconds / DAY_SECONDS)
  const hours = Math.floor((seconds % DAY_SECONDS) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}
