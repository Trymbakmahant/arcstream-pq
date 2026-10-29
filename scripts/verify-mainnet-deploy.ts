/**
 * Read-only review of an ArcStreamVault you deployed to Arc Mainnet. It sends no transactions and
 * needs no keys. Usage: bun run mainnet:check 0xYourVaultAddress
 *
 * Checks: the RPC really is Arc Mainnet (5042); code exists at the address; the deployed runtime code equals
 * the locally compiled artifact (immutable slots masked); usdc() is the expected USDC; the PQ precompile
 * constant is correct; no escrows exist yet; and Arc's PQ precompile is live (it rejects a malformed key).
 */
import { readFileSync } from 'node:fs'
import { createPublicClient, getAddress, http, isAddress, type Address, type Hex } from 'viem'
import { arcStreamVaultAbi } from '../src/contracts/arcStreamVaultAbi'
import { ARC_MAINNET } from '../src/contracts/mainnet'

const input = process.argv[2]
if (!input || !isAddress(input)) {
  console.error('Usage: bun run mainnet:check 0xYourVaultAddress')
  process.exit(2)
}
const vault = getAddress(input)
// ARC_RPC_URL / EXPECT_CHAIN_ID let you rehearse this check against Arc Testnet; the defaults are Arc Mainnet.
const rpcUrl = process.env.ARC_RPC_URL ?? ARC_MAINNET.rpcUrl
const expectedChainId = Number(process.env.EXPECT_CHAIN_ID ?? ARC_MAINNET.chainId)
const client = createPublicClient({ transport: http(rpcUrl) })

interface Artifact {
  deployedBytecode: { object: Hex; immutableReferences?: Record<string, { start: number; length: number }[]> }
}
const artifact = JSON.parse(
  readFileSync(new URL('../contracts/out/ArcStreamVault.sol/ArcStreamVault.json', import.meta.url), 'utf8'),
) as Artifact

const results: [string, boolean, string][] = []
const check = (name: string, ok: boolean, detail = '') => results.push([name, ok, detail])

const chainId = await client.getChainId()
check(`RPC chain id is ${expectedChainId}`, chainId === expectedChainId, `chain id ${chainId}`)

const code = (await client.getCode({ address: vault })) ?? '0x'
check('Contract code exists', code !== '0x', `${(code.length - 2) / 2} bytes`)

// Mask immutable slots (usdc address) before comparing runtime code with the artifact.
const expected = artifact.deployedBytecode.object.slice(2).toLowerCase()
const actual = code.slice(2).toLowerCase()
const mask = (hex: string) => {
  let out = hex
  for (const refs of Object.values(artifact.deployedBytecode.immutableReferences ?? {})) {
    for (const { start, length } of refs) {
      out = out.slice(0, start * 2) + '0'.repeat(length * 2) + out.slice(start * 2 + length * 2)
    }
  }
  return out
}
// The compiler appends a metadata hash; compare everything before it.
const trim = (hex: string) => hex.slice(0, hex.length - 106)
check('Runtime code matches local build', trim(mask(actual)) === trim(mask(expected)), 'immutables masked, metadata ignored')

const read = async <T,>(functionName: 'usdc' | 'ARC_PQ_PRECOMPILE' | 'escrowCount'): Promise<T> =>
  (await client.readContract({ address: vault, abi: arcStreamVaultAbi, functionName })) as T
const usdc = await read<Address>('usdc').catch(() => undefined)
check('usdc() is the expected USDC', usdc?.toLowerCase() === ARC_MAINNET.usdc.toLowerCase(), String(usdc))
const pq = await read<Address>('ARC_PQ_PRECOMPILE').catch(() => undefined)
check('PQ precompile address', pq?.toLowerCase() === ARC_MAINNET.pqPrecompile.toLowerCase(), String(pq))
const count = await read<bigint>('escrowCount').catch(() => undefined)
check('No escrows yet (fresh deploy)', count === 0n, String(count))

const probe = await client
  .call({ to: ARC_MAINNET.pqPrecompile, data: '0xbf4db8ba' })
  .then(() => false)
  .catch(() => true)
check('PQ precompile is live (rejects malformed input)', probe)

for (const [name, ok, detail] of results) console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`)
console.log(`\nExplorer: ${ARC_MAINNET.explorerUrl}/address/${vault}`)
if (results.some(([, ok]) => !ok)) process.exit(1)
