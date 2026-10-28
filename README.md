# ArcStreamVault

A USDC milestone escrow on Arc Testnet. An employer deposits USDC up front, the contractor submits proof of work per milestone, the employer approves it, and the contractor claims the payout. Unstarted milestones can be refunded to the employer, and both parties can agree to split any remaining funds if they disagree.

Employers can optionally lock an escrow with Touch ID / Face ID, so releasing or refunding as the employer needs a biometric check on top of the wallet signature.

The web app has two pages: a public landing page at `/` and the product dashboard at `/dashboard`. The dashboard has two workspaces: an employer view to fund escrows and approve work, and a contractor view to submit proof and claim payouts.

Built with [Arc Studio](https://studio.arc.io)

## Tech stack

- Solidity ^0.8.24, OpenZeppelin Contracts, Foundry (contract and tests)
- React, Vite, TypeScript, Tailwind CSS (web app)
- wagmi, viem, ConnectKit (wallet and chain access)

## Development

Prerequisites: [Bun](https://bun.sh) and [Foundry](https://book.getfoundry.sh).

```bash
bun install
forge build
forge test
bun run dev
```

The contract lives in `contracts/ArcStreamVault.sol` and its tests in `contracts/test/`. After deploying, set the contract address in `src/contracts/vault.ts`. If the contract changes, rebuild and regenerate `src/contracts/arcStreamVaultAbi.ts` from `contracts/out/ArcStreamVault.sol/ArcStreamVault.json`.

When hosting the built app, configure a single-page-app fallback so `/dashboard` serves `index.html`.

### Environment variables

None.
