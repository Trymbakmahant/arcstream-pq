import { formatUnits, parseUnits } from 'viem'

/** USDC ERC-20 decimals on Arc Testnet. The native gas view uses 18 decimals; this app only uses the ERC-20 view. */
export const USDC_DECIMALS = 6

const PLAIN_DECIMAL = /^\d+(\.\d{1,6})?$|^\.\d{1,6}$/

/** Parse a user-entered USDC amount; throws when it is not a plain decimal with at most 6 fraction digits. */
export function parseUsdc(value: string): bigint {
  const trimmed = value.trim()
  if (!PLAIN_DECIMAL.test(trimmed)) {
    throw new Error(`'${value}' is not a valid USDC amount`)
  }
  return parseUnits(trimmed.startsWith('.') ? `0${trimmed}` : trimmed, USDC_DECIMALS)
}

/** Display a raw USDC amount (6-decimal ERC-20 view) with thousands separators, truncated to fractionDigits. */
export function fmtUsdc(raw: bigint, fractionDigits = 2): string {
  const [whole, fraction = ''] = formatUnits(raw, USDC_DECIMALS).split('.')
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  if (fractionDigits === 0) return grouped
  return `${grouped}.${fraction.padEnd(fractionDigits, '0').slice(0, fractionDigits)}`
}

export const shortAddress = (value: string) => `${value.slice(0, 6)}...${value.slice(-4)}`
