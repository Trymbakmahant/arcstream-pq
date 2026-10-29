# ArcStream-PQ: Post-Quantum Milestone Escrow with Anti-Ghosting Protocol & Commercial Settlement Invoicing

> **Built with [Arc Studio](https://studio.arc.io)** for the **DoraHacks Arc Microgrants Round 2**

ArcStream-PQ is an institutional-grade, noncustodial USDC milestone escrow protocol deployed natively on the **Arc Network**. It combines **Arc's native Post-Quantum SLH-DSA-SHA2-128s signature precompile**, biometric hardware passkeys (Touch ID / Face ID via WebAuthn PRF), an **Anti-Ghosting Review Window protocol**, and **Commercial Tax Invoice / Settlement Receipts** to eliminate counterparty risk, ghosting, and quantum threats.

---

## ⚡ What Makes ArcStream-PQ Unique?

1. **Post-Quantum 2FA (Arc Native Precompile)**:
   - Verifies stateless hash-based signatures (`SLH-DSA-SHA2-128s`, FIPS 205) directly onchain at precompile `0x1800000000000000000000000000000000000004`.
   - Employer releases and refunds are bound to biometric passkeys via WebAuthn PRF master seed derivation. Even if an employer's ECDSA wallet key is stolen, the attacker **cannot drain or refund funds** without physical biometric authorization.
2. **Anti-Ghosting Review Window Protocol**:
   - Solves the classic Web3 "ghosting employer" deadlock. Employers set an inspection period (1 to 30 days, default 7 days) at escrow creation.
   - If an employer fails to review submitted work before the inspection deadline expires, the contractor can independently call `claimUncontestedMilestone()` to release their payout.
3. **Universal Deliverable Proof Resolver**:
   - Supports any work deliverable format: interactive preview links for IPFS CIDs (`ipfs://` / gateway), secure web URLs (Figma, GitHub, Loom, Google Drive), or cryptographic commit hashes with 1-click clipboard actions.
4. **Commercial Tax Invoice & Settlement Receipts**:
   - Instant 1-click generation of print-ready, B2B tax/accounting receipts (`window.print()`).
   - Includes official invoice IDs (`ARC-INV-...`), counterparty hex addresses, line-item deliverables, Arc block explorer transaction links, and an official **Post-Quantum Cryptographic Security Seal**.
5. **Native USDC Gas & Fiat Onramp**:
   - Arc uses USDC natively for gas—no secondary token swaps or multi-token balance management required.
   - Integrated with Circle Onramp widget for direct fiat-to-USDC onboarding.

---

## 📐 Protocol Architecture

```
┌────────────────────────────────────────────────────────┐
│                   EMPLOYER WORKFLOW                    │
├────────────────────────────────────────────────────────┤
│ 1. Connects wallet & selects Review Window (1-30 days) │
│ 2. Arms PQ Shield: Touch ID unlocks WebAuthn PRF seed  │
│ 3. Derives 32-byte SLH-DSA public key in-memory        │
│ 4. Deposits USDC to fund milestone agreement           │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                  CONTRACTOR DELIVERY                   │
├────────────────────────────────────────────────────────┤
│ 1. Submits work proof (Figma, GitHub, Loom, IPFS CID)  │
│ 2. Milestone timestamp `submittedAt` is recorded       │
│ 3. Review Window countdown timer activates             │
└───────────────────────────┬────────────────────────────┘
                            │
               ┌────────────┴────────────┐
               ▼                         ▼
   [Path A: Employer Approves]   [Path B: Employer Inactive]
   Touch ID signs SLH-DSA proof  Review window expires
   Contract validates at 0x18..4 Contractor calls
   Instant payout to contractor  claimUncontestedMilestone()
               │                         │
               └────────────┬────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│       COMMERCIAL INVOICE & PROOF OF SETTLEMENT         │
├────────────────────────────────────────────────────────┤
│ Generate print-ready PDF invoice with Arc tx hash and  │
│ Post-Quantum Cryptographic Precompile verification seal│
└────────────────────────────────────────────────────────┘
```

---

## 🚀 Deployed Contracts

| Network | Contract | Address | Explorer / Precompile |
| :--- | :--- | :--- | :--- |
| **Arc Testnet** (5042002) | `ArcStreamVault` | `0x464504fe41fef085413c52cfc6fdbeb15637c0fd` | [View on Arc Explorer](https://explorer.testnet.arc.io/address/0x464504fe41fef085413c52cfc6fdbeb15637c0fd) |
| **Arc Testnet PQ Precompile** | `IArcPQ (FIPS 205)` | `0x1800000000000000000000000000000000000004` | Native Protocol Precompile (`verifySlhDsaSha2128s`) |
| **Official USDC** | Native ERC-20 View | `0x3600000000000000000000000000000000000000` | Native USDC (6 Decimals) |
| **Arc Mainnet** (5042) | Configured in App | Dynamic Switcher | Ready for deployment (`docs/mainnet-deploy.md`) |

*Superseded deployments: `0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53`, `0xbfeba9a6fe6b81f583417d426a3957d713f30965`.*

---

## 🛠️ Tech Stack

- **Smart Contracts**: Solidity 0.8.28 + Foundry (`forge`). Sources in `contracts/`, tests in `contracts/test/`.
- **Frontend**: React 18, Vite, TypeScript, Tailwind CSS v3 (brand tokens: `brandMain` #e8e9df, `brandSecondary` #a9bb87, `brandHighlight` #2e3d28).
- **Web3 Connectivity**: Wagmi v2, Viem v2, ConnectKit.
- **Post-Quantum Cryptography**: `@noble/post-quantum` (SLH-DSA-SHA2-128s), WebAuthn PRF extension, background Web Workers.
- **Ecosystem Tooling**: Arc Studio CLI (`@circle-fin/arc-studio-cli`), Circle AppKit, Circle Web3 Services.

---

## 💻 Quickstart & Local Development

### Prerequisites
- [Bun](https://bun.sh) (v1.1+)
- [Foundry](https://book.getfoundry.sh) (`forge`, `cast`, `anvil`)

```bash
# 1. Install dependencies
bun install

# 2. Run Foundry smart contract test suite (388 tests across 21 suites)
forge test
# or
bun run contracts:test

# 3. Test Arc Testnet native PQ precompile live
bun run pq:check

# 4. TypeScript typecheck
bun run typecheck

# 5. Start local Vite development server
bun run dev

# 6. (Optional) Run Circle Onramp sandbox mock API
bun run dev:api
```

---

## 🧪 Verification & Audit Suite

- **Full Test Suite**: **388 automated tests** passing across 21 test suites (`ArcStreamVault.Uncontested.t.sol`, `ArcStreamVault.Inspection.t.sol`, `ArcStreamVault.PQPrecompile.t.sol`, etc.).
- **Invariant Testing**: `ArcStreamVault.Invariant.t.sol` fuzzes settlement remainders, multi-party balance invariants, and proves uncontested payouts remain mathematically bounded.
- **Precompile Live Verification**: `scripts/verify-pq-precompile.ts` tests real cryptographic signing and staticcall execution against the Arc Testnet RPC.
- **Mainnet Deploy Verification**: `scripts/verify-mainnet-deploy.ts` verifies bytecode immutables, deployed runtime code, and precompile liveness on Arc Mainnet (`bun run mainnet:check <address>`).

---

## 📜 License

MIT License. Built for the Arc & Circle ecosystem.
