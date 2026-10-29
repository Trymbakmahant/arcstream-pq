# ArcStream-PQ: Quantum-Safe USDC Milestone Escrow

> **Built with [Arc Studio](https://studio.arc.io)** for the **DoraHacks Arc Microgrants Round 2**.

ArcStream-PQ is a noncustodial, post-quantum milestone escrow protocol on Arc. Employers fund escrows in native USDC, contractors submit verifiable proof of work per milestone, employers approve, and contractors claim payouts.

Employer releases and refunds can require a **hardware-backed post-quantum signature (NIST FIPS 205 SLH-DSA-SHA2-128s)** unlocked via **Touch ID / Face ID (WebAuthn PRF)** and verified by **Arc's Native Signature Precompile (`0x1800...0004`)**.

---

## ⚡ Key Highlights

- **Arc Native Post-Quantum Verification**: Directly invokes Arc's native precompile `0x1800000000000000000000000000000000000004` to verify 7,856-byte SLH-DSA-SHA2-128s signatures onchain before releasing funds.
- **Biometric Hardware 2FA (Zero Keys on Disk)**: WebAuthn PRF unlocks a 32-byte master seed inside your device's Secure Enclave. A background Web Worker derives the post-quantum keypair on-demand in RAM and discards it immediately after signing.
- **USDC-Native Gas & Settlement**: All payments, balances, and gas fees on Arc are denominated natively in USDC. No secondary gas token (ETH/MATIC) is needed.
- **Circle Onramp & CCTP Ready**: Includes instant "Fund with USDC" modal supporting Circle Faucet (Testnet) and Circle CCTP / Arc Portal fiat onramp (Mainnet).
- **Rigorously Tested**: 285 automated test suites passing, covering invariant testing, stateful fuzzing, reentrancy guards, and precompile failure edge-cases.

---

## 📐 Architecture

```
┌────────────────────────────────────────────────────────┐
│                   EMPLOYER WORKFLOW                    │
├────────────────────────────────────────────────────────┤
│ 1. Employer connects wallet & arms PQ Shield           │
│ 2. Touch ID unlocks WebAuthn PRF master seed in memory │
│ 3. Derives 32-byte SLH-DSA public key                  │
│ 4. Deposits USDC to create Milestone Escrow            │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                  CONTRACTOR DELIVERY                   │
├────────────────────────────────────────────────────────┤
│ 1. Contractor submits milestone proof (GitHub/IPFS)    │
│ 2. Payout status updates to "Awaiting Approval"        │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│         QUANTUM-SAFE RELEASE (BIOMETRIC 2FA)           │
├────────────────────────────────────────────────────────┤
│ 1. Employer clicks "Approve & Release"                 │
│ 2. Touch ID prompts biometric hardware verification    │
│ 3. Worker signs 32-byte domain digest with SLH-DSA-128s│
│ 4. Transmits 7,856-byte signature in calldata          │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│             ARCSTREAM VAULT SMART CONTRACT             │
├────────────────────────────────────────────────────────┤
│ staticcall ARC_PQ_PRECOMPILE (0x1800...0004)           │
│ verifySlhDsaSha2128s(pubKey, messageDigest, signature) │
│                        │                               │
│                 ✅ Verification OK                     │
│                        │                               │
│       Transfers milestone USDC directly to Contractor  │
└────────────────────────────────────────────────────────┘
```

---

## 🚀 Contracts & Deployments

| Network | Contract | Address | Explorer Link |
| :--- | :--- | :--- | :--- |
| **Arc Testnet** (5042002) | `ArcStreamVault` | `0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53` | [View on Arc Explorer](https://explorer.testnet.arc.io/address/0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53) |
| **Arc Testnet Precompile** | `IArcPQ (FIPS 205)` | `0x1800000000000000000000000000000000000004` | Native Protocol Precompile |
| **Official USDC** | Native ERC-20 View | `0x3600000000000000000000000000000000000000` | Native USDC (6 Decimals) |

---

## 🛠️ Tech Stack

- **Smart Contracts**: Solidity 0.8.28 + Foundry (`forge`). Sources in `contracts/`, tests in `contracts/test/`.
- **Frontend**: React 18, Vite, TypeScript, Tailwind CSS v3 (brand tokens: `brandMain` #e8e9df, `brandSecondary` #a9bb87, `brandHighlight` #2e3d28).
- **Web3 Connectivity**: Wagmi v2, Viem v2, ConnectKit.
- **Post-Quantum Cryptography**: `@noble/post-quantum` (SLH-DSA-SHA2-128s), WebAuthn PRF extension, background Web Workers.
- **Ecosystem Tooling**: Arc Studio CLI (`@circle-fin/arc-studio-cli`), Circle AppKit, Circle Web3 Services.

---

## 💻 Local Development

### Prerequisites
- [Bun](https://bun.sh) (v1.1+)
- [Foundry](https://book.getfoundry.sh) (`forge`, `cast`, `anvil`)

```bash
# 1. Install dependencies
bun install

# 2. Run Foundry smart contract test suite (285 tests)
bun run contracts:test

# 3. Test Arc Testnet native PQ precompile live
bun run pq:check

# 4. TypeScript typecheck
bun run typecheck

# 5. Start local Vite development server
bun run dev
```

---

## 🧪 Verification & Audit Suite

- **Invariant Testing**: `ArcStreamVault.Invariant.t.sol` fuzzes settlement remainders, multi-party balance invariants, and ensures quantum-protected actions cannot be bypassed under any sequence of calls.
- **Precompile Verification**: `scripts/verify-pq-precompile.ts` tests real live cryptographic signing and precompile execution against Arc Testnet RPC.
- **Mainnet Deploy Verification**: `scripts/verify-mainnet-deploy.ts` verifies bytecode immutables, deployed runtime code, and precompile liveness on Arc Mainnet.

---

## 📜 License

MIT License. Built for the Arc & Circle ecosystem.
