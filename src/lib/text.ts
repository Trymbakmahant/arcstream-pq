/** Longest milestone description accepted by the form (characters). Stored onchain as a string. */
export const MAX_DESCRIPTION_LENGTH = 1000

/** The contract stores a single description string. The first non-empty line doubles as the milestone title. */
export function milestoneTitle(description: string, maxLength = 80): string {
  const firstLine =
    description
      .split('\n')
      .map((line) => line.trim())
      .find((line) => line.length > 0) ?? ''
  const cleaned = firstLine.replace(/^(#{1,6}\s+|[-*\u2022]\s+|\d+[.)]\s+)/, '')
  if (!cleaned) return 'Untitled milestone'
  return cleaned.length > maxLength ? `${cleaned.slice(0, maxLength - 1)}\u2026` : cleaned
}
