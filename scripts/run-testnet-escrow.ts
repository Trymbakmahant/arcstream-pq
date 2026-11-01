import { createPublicClient, createWalletClient, http, erc20Abi, formatUnits } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { arcTestnet } from 'viem/chains'
import { arcStreamVaultAbi } from '../src/contracts/arcStreamVaultAbi'

const TEST_PRIVATE_KEY = '0x0755658de407907e0457d51bd7caceb4448306c462e022308ce915458cc1d476'
const account = privateKeyToAccount(TEST_PRIVATE_KEY)

const VAULT_ADDRESS = '0x464504fe41fef085413c52cfc6fdbeb15637c0fd'
const USDC_ADDRESS = '0x3600000000000000000000000000000000000000'

// A mock contractor address to receive milestones
const CONTRACTOR = '0x34Bc1A562b39904F1A5B0793fD65aD44ee8dd38a' // The user's wallet!

const publicClient = createPublicClient({
  chain: arcTestnet,
  transport: http(arcTestnet.rpcUrls.default.http[0]),
})

const walletClient = createWalletClient({
  account,
  chain: arcTestnet,
  transport: http(arcTestnet.rpcUrls.default.http[0]),
})

async function main() {
  console.log('🤖 Test Wallet Address:', account.address)
  
  const nativeBalance = await publicClient.getBalance({ address: account.address })
  const tokenBalance = await publicClient.readContract({
    address: USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [account.address],
  })

  console.log(`💰 Native Balance (Gas): ${formatUnits(nativeBalance, 18)} USDC`)
  console.log(`💰 ERC-20 Token Balance: ${formatUnits(tokenBalance, 6)} USDC`)

  if (tokenBalance === 0n) {
    console.log('\n⚠️  Wallet not funded yet!')
    console.log(`Please drip 10 USDC from https://faucet.circle.com to:\n${account.address}\n`)
    return
  }

  const milestoneAmount = 1_000_000n // 1.00 USDC
  const total = milestoneAmount * 2n // 2.00 USDC

  console.log(`\n1️⃣ Checking USDC Allowance to Vault (${VAULT_ADDRESS})...`)
  const currentAllowance = await publicClient.readContract({
    address: USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [account.address, VAULT_ADDRESS],
  })
  console.log(`   Current Allowance: ${formatUnits(currentAllowance, 6)} USDC`)

  if (currentAllowance < total) {
    console.log('   Approving 10 USDC to Vault...')
    const approveTx = await walletClient.writeContract({
      address: USDC_ADDRESS,
      abi: erc20Abi,
      functionName: 'approve',
      args: [VAULT_ADDRESS, 10_000_000n],
    })
    console.log(`   Approval Tx submitted: ${approveTx}`)
    const receipt = await publicClient.waitForTransactionReceipt({ hash: approveTx })
    console.log(`   ✅ Approval confirmed in block ${receipt.blockNumber}`)
  } else {
    console.log('   ✅ Allowance already sufficient.')
  }

  console.log('\n2️⃣ Creating Escrow on Arc Testnet...')
  console.log(`   Employer:   ${account.address}`)
  console.log(`   Contractor: ${CONTRACTOR}`)
  console.log(`   Milestones: 2 milestones @ 1 USDC each = 2 USDC total`)

  const createTx = await walletClient.writeContract({
    address: VAULT_ADDRESS,
    abi: arcStreamVaultAbi,
    functionName: 'createEscrow',
    args: [
      CONTRACTOR,
      [milestoneAmount, milestoneAmount],
      ['Milestone 1: Project Setup', 'Milestone 2: Final Delivery'],
      '0x', // Empty PQ public key (or can be provided)
      604800n, // 7 days review window
    ],
  })

  console.log(`   CreateEscrow Tx submitted: ${createTx}`)
  const receipt = await publicClient.waitForTransactionReceipt({ hash: createTx })
  console.log(`   🎉 Escrow created successfully in block ${receipt.blockNumber}!`)
  console.log(`   Explorer Link: https://explorer.testnet.arc.io/tx/${createTx}`)

  const count = await publicClient.readContract({
    address: VAULT_ADDRESS,
    abi: arcStreamVaultAbi,
    functionName: 'escrowCount',
  })
  console.log(`   Current Total Vault Escrows: ${count}`)
}

main().catch((err) => {
  console.error('❌ Error executing escrow flow:', err)
  process.exit(1)
})

