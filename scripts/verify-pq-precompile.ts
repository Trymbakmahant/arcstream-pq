/**
 * Live check of the post-quantum path against Arc Testnet (read-only eth_call, no wallet needed).
 *
 * 1. Derives an SLH-DSA-SHA2-128s key from a throwaway master secret using the app's own seed derivation.
 * 2. Reads pqSigningMessage from the deployed vault and checks it equals the app's local digest.
 * 3. Signs that digest and calls Arc's PQ Signature Verify precompile (0x1800...0004): expects true,
 *    then false for a different message.
 *
 * Run: bun run pq:check
 */
import { slh_dsa_sha2_128s } from '@noble/post-quantum/slh-dsa.js'
import { arcTestnet } from 'viem/chains'
import { bytesToHex, createPublicClient, encodeFunctionData, hexToBytes, http, keccak256, toHex, type Hex } from 'viem'
import { arcStreamVaultAbi, VAULT_ADDRESS } from '../src/contracts/vault'
import { seedFromMaster, signingMessage } from '../src/lib/pq'

const PRECOMPILE = '0x1800000000000000000000000000000000000004'
const verifyAbi = [
  {
    type: 'function',
    name: 'verifySlhDsaSha2128s',
    stateMutability: 'view',
    inputs: [
      { name: 'vk', type: 'bytes' },
      { name: 'message', type: 'bytes' },
      { name: 'sig', type: 'bytes' },
    ],
    outputs: [{ type: 'bool' }],
  },
] as const

if (!VAULT_ADDRESS) throw new Error('Vault address is not set')
const client = createPublicClient({ chain: arcTestnet, transport: http(arcTestnet.rpcUrls.default.http[0]) })

const master = keccak256(toHex('pq-check-throwaway-master'))
const { secretKey, publicKey } = slh_dsa_sha2_128s.keygen(hexToBytes(seedFromMaster(master)))

const local = signingMessage({ chainId: arcTestnet.id, vault: VAULT_ADDRESS, escrowId: 1n, action: 0 })
const onchain = await client.readContract({
  address: VAULT_ADDRESS,
  abi: arcStreamVaultAbi,
  functionName: 'pqSigningMessage',
  args: [1n, 0n],
})
console.log('digest matches deployed vault:', local === onchain)

const signature = slh_dsa_sha2_128s.sign(hexToBytes(local), secretKey)
const verify = async (message: Hex): Promise<boolean> => {
  const data = encodeFunctionData({
    abi: verifyAbi,
    functionName: 'verifySlhDsaSha2128s',
    args: [bytesToHex(publicKey), message, bytesToHex(signature)],
  })
  const result = await client.call({ to: PRECOMPILE, data })
  return result.data === `0x${'0'.repeat(63)}1`
}

const okValid = await verify(local)
const okWrong = await verify(signingMessage({ chainId: arcTestnet.id, vault: VAULT_ADDRESS, escrowId: 1n, action: 1 }))
console.log('precompile accepts the app signature:', okValid)
console.log('precompile rejects a different action:', !okWrong)
if (local !== onchain || !okValid || okWrong) process.exit(1)
