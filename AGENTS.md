# ArcStreamVault

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app.

## What This App Does

USDC milestone escrow on Arc Testnet. Employers fund escrows, contractors submit proof of work per milestone, employers approve, contractors claim payouts. Includes refund of unstarted milestones and a mutual-cancel split.

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS v3 (brand tokens `brandMain` #e8e9df, `brandSecondary` #a9bb87, `brandHighlight` #2e3d28)
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, tests in `contracts/test/*.t.sol`. `bun run contracts:build`, `bun run contracts:test`.
- Chain: Arc Testnet (Chain ID 5042002, from `viem/chains`)
- Token: USDC ERC-20 view, 6 decimals, 0x3600000000000000000000000000000000000000

## Deployments

- ArcStreamVault (Arc Testnet, current, with Arc Native SLH-DSA-SHA2-128s PQ Precompile): 0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53
  - tx: 0x87239976031b6b7fc60da6105e9679e7b5f2c669fe654871b0f16136f3d6118f
  - explorer: https://explorer.testnet.arc.io/address/0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53
  - Precompile: Arc Native PQ Signature Verify (0x1800000000000000000000000000000000000004)
- Superseded:
  - 0xbfeba9a6fe6b81f583417d426a3957d713f30965 (Merkle tree one-time hash commitments)
  - 0xb6ed26ff733fe4f66cc4015126707c6e5b04e497 (No second factor)
  - constructor arg: USDC 0x3600000000000000000000000000000000000000
  - Wired in `src/contracts/vault.ts` and `src/contracts/arcStreamVaultAbi.ts`

## Key Files

- Routes (tiny History API router in `src/lib/router.tsx`): `/` landing (`src/pages/Landing.tsx`, `src/components/landing/`), `/dashboard` product (`src/pages/Dashboard.tsx`).
- `src/components/dashboard/` - Redesigned Dashboard UI (Sidebar, TopBar, StatCards, EscrowsPanel, EscrowTable, CreateEscrowModal, PanelStates)
- `src/components/` - Common UI (TaskDetailsDrawer, SubmitWorkModal, PqAuthModal, TxProvider)
- `src/hooks/` - contract reads/writes (`useEscrows`, `useVaultActions`, `usePasskey`, etc.)
- `src/lib/pq.ts` & `src/lib/pq.worker.ts` - SLH-DSA-SHA2-128s key derivation and background worker signing
- `scripts/verify-pq-precompile.ts` - Live Arc Testnet verification (`bun run pq:check`)

## To Run

```bash
bun install
bun run dev          # Local Vite dev server
bun run pq:check     # Test PQ precompile live on Arc Testnet
bun run contracts:test # Run Forge contract test suite
bun run typecheck    # TypeScript verification
```

## Post-Quantum Second Factor (How it Works)

- **Contract**: Optional `pqPublicKey` (32 bytes) per escrow. Employer `releaseMilestone` (action = milestone index) and `refundRemaining` (action = milestoneCount) staticcalls Arc's native precompile `0x1800000000000000000000000000000000000004` (`verifySlhDsaSha2128s`) with the 32-byte domain-bound digest `pqSigningMessage(escrowId, action)`.
- **Browser**: `src/lib/webauthn.ts` uses Touch ID / Face ID platform passkey (WebAuthn PRF extension) to unlock a 32-byte master secret; `src/lib/pq.ts` and `src/lib/pq.worker.ts` derive the SLH-DSA keypair in-memory on demand and sign the action digest.
- **Security**: The signing key is never persisted in storage. Replaying transactions or mempool snooping cannot steal funds or redirect payouts.

