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

- ArcStreamVault (Arc Testnet, current: SLH-DSA precompile factor + inspection window): 0x464504fe41fef085413c52cfc6fdbeb15637c0fd
  - tx 0x571bc7bad262af6a98ee95352d9a43734c14286676fde496141017254657cfce
- Superseded (SLH-DSA, no inspection window): 0x885ffa04b92eaa3d0fd11c3b05f425bcbe26de53
- Superseded (Merkle second factor, no escrows): 0xbfeba9a6fe6b81f583417d426a3957d713f30965
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

## Post-quantum second factor (how it really works)

- Arc exposes a PQ Signature Verify precompile at 0x1800000000000000000000000000000000000004 (SLH-DSA-SHA2-128s, FIPS 205). Interface: `verifySlhDsaSha2128s(bytes vk, bytes message, bytes sig) returns (bool)`; vk is 32 bytes, sig is 7,856 bytes, malformed lengths revert, ~380k gas. Confirmed against arc-node `crates/precompiles/src/pq.rs` and the live testnet (`bun run pq:check`).
- Contract: `createEscrow(..., bytes pqPublicKey)` stores the 32-byte key (empty = unprotected) after probing that the precompile exists. Employer `releaseMilestone` (action = milestone index) and `refundRemaining` (action = milestoneCount) must pass the signature over `pqSigningMessage(escrowId, action)` (domain: chainid, vault, escrowId, action). Contractor claims never need it. Foundry tests mock the precompile (`contracts/test-helpers/MockArcPQ.sol`).
- Browser: `src/lib/webauthn.ts` unlocks a 32-byte master secret with a Touch ID / Face ID passkey (WebAuthn PRF when available, else a device-bound secret in localStorage). `src/lib/pq.ts` + `pq.worker.ts` derive the SLH-DSA key in memory and sign in a Web Worker (a few seconds).
- Honest limits: the passkey's own P-256 signature is never used onchain and is not post-quantum; the wallet key stays ECDSA, so a stolen wallet key can still approve milestones (which pays the contractor) but cannot release or refund a protected escrow. Losing the passkey (or switching browser/device without PRF) means the PQ key cannot be rebuilt: employer release/refund is blocked, contractor claims and mutualCancel still work. If a hardfork disabled the precompile, mutualCancel is the recovery path. WebAuthn is usually blocked inside the Arc Studio preview iframe; test in its own tab.

## Mainnet

- ArcStreamVault (Arc Mainnet, Chain ID 5042): 0xbe207b904f08036A483E15a46eE476A712944cBF
  - tx 0x68b205b803c768c2a42ebcb283c0a8489c14788a3a6f6af75eade87d9a1fee3f
  - Constructor arg: USDC 0x3600000000000000000000000000000000000000
  - Verified with `bun run mainnet:check 0xbe207b904f08036A483E15a46eE476A712944cBF` (7/7 checks passed).
- Arc Studio does not deploy to mainnet. `docs/mainnet-deploy.md` has the user-run `arc-forge create` command; `src/contracts/mainnet.ts` is wired with the live deployment address and tx hash.
- Funding UX: the Fund with USDC modal (testnet faucet link, mainnet CCTP/bridge docs). No Circle Onramp backend and no Gas Station by decision; Arc gas is USDC.
- Network switch: `src/lib/network.ts` holds Arc Testnet and Arc Mainnet settings; the choice is stored in localStorage (`arcstream.network`) and switching reloads the app. Mainnet vault/tx hash come from `src/contracts/mainnet.ts` (still undefined until the user deploys); until then mainnet shows the not-deployed state.
- Circle Onramp: Arc Testnet embeds the Onramp sandbox widget inside the Fund modal (`OnrampSection.tsx`); a Bun API in `server/onramp.ts` (run `bun run dev:api`, port 8787, proxied at `/api` by `vite.config.ts`) mints sessions with `CIRCLE_API_KEY` after the wallet signs a short proof message. Arc Mainnet shows a button to Arc's hosted page `portal.arc.io/deposit/fiat` (no key). Sandbox may not deliver USDC on Arc Testnet; production cards need a mainnet key plus KYB. The API server must be running wherever the app is hosted for the embedded widget.
- Inspection window: createEscrow takes a review period (0 = 7 days, 1 to 30 days). If the employer does not approve within it after the latest proof, the contractor calls claimUncontestedMilestone. There is deliberately no employer reject/dispute path yet; disputes go through mutualCancel (needs the contractor's consent).
