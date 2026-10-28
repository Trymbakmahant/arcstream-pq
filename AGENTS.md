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

- ArcStreamVault (Arc Testnet, current, with biometric second factor): 0xbfeba9a6fe6b81f583417d426a3957d713f30965
  - tx 0x0d8a668fc76ac942d4436ef4c9314e5df46d95bbdc19bd84c60ec27a2d12d87a
- Superseded (no second factor, no escrows): 0xb6ed26ff733fe4f66cc4015126707c6e5b04e497
  - constructor arg: USDC 0x3600000000000000000000000000000000000000
  - Wired in `src/contracts/vault.ts` (address) and `src/contracts/arcStreamVaultAbi.ts` (ABI from forge artifact)

## Key Files

- Routes (tiny History API router in `src/lib/router.tsx`): `/` landing (`src/pages/Landing.tsx`, `src/components/landing/`), `/dashboard` product (`src/pages/Dashboard.tsx`). Hosts need an SPA fallback.

- `src/App.tsx` - tabs (Employer / Contractor)
- `src/components/` - UI (Header, CreateEscrowCard, EscrowCard, SubmitWorkModal, TxProvider)
- `src/hooks/` - contract reads/writes
- `src/config.ts` - wagmi config
- No injected `@/onchain-facts` / `@/onchain-money` helpers exist in this project; do not import them.

## To Run

```bash
bun install
bun run dev
```

## Biometric second factor (how it really works)

- Contract: optional `pqCommitment` (Merkle root of one-time hash secrets) per escrow. Employer `releaseMilestone` (action = milestone index) and `refundRemaining` (action = milestoneCount) must pass `abi.encode(bytes32 secret, bytes32[] path)`. Contractor claims never need it.
- Browser: `src/lib/webauthn.ts` uses a Touch ID / Face ID platform passkey (WebAuthn, PRF extension when available) to unlock a master secret; `src/lib/pq.ts` builds the tree and proofs. Proofs are cross-checked against the contract in `contracts/test/ArcStreamVault.TsVector.t.sol`.
- Honest limits: the passkey signature is never verified onchain and P-256 is not post-quantum; protection comes from the hash commitments. A stolen wallet key can still approve milestones (which pays the contractor). Secrets live per browser/passkey: losing it blocks employer release/refund (mutualCancel is the recovery path). WebAuthn is usually blocked inside the Arc Studio preview iframe; test in its own tab.
