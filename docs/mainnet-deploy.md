# Deploy ArcStreamVault to Arc Mainnet (you run this, not Arc Studio)

> Warning: Transactions on mainnet involve real funds and, once submitted, are irreversible. Arc Studio does not deploy to, transact on, sign for, or fund anything on mainnet. You are responsible for reviewing, testing, deploying and operating this code. Get an independent professional audit first.

## Values (from the official Arc docs; check them yourself)

| Item | Value | Source |
| --- | --- | --- |
| Network | Arc Mainnet | docs.arc.io/arc/references/connect-to-arc |
| Chain ID | 5042 | same |
| RPC | https://rpc.mainnet.arc.io | same |
| Explorer | https://explorer.arc.io | same |
| USDC (ERC-20 interface, 6 decimals) | 0x3600000000000000000000000000000000000000 | docs.arc.io/arc/references/contract-addresses |
| PQ Signature Verify precompile | 0x1800000000000000000000000000000000000004 | arc-node `crates/precompiles` |

Read-only checks I made against mainnet RPC: USDC `symbol()` is USDC, `decimals()` is 6, and the PQ precompile rejects a malformed key with "Invalid verifying key length", so it is live.

## Before you deploy

1. Use a fresh deployer wallet you control, funded with a small amount of native USDC for gas (Arc gas is USDC; the mempool enforces a 20 Gwei `maxFeePerGas` floor). Do not paste your private key into any chat or file.
2. Install Arc Foundry (`arc-forge`, `arc-cast`): https://docs.arc.io/arc/tutorials/install-arc-foundry
3. Build and test with the Arc-aware tools:
   ```bash
   arc-forge build
   arc-forge test --network arc
   ```
   The repo's own `forge test` run is 285 passing, with the PQ precompile mocked.
4. Put your key in an environment variable in your own shell:
   ```bash
   export PRIVATE_KEY=<your deployer key>      # never commit this
   export ARC_MAINNET_RPC_URL=https://rpc.mainnet.arc.io
   ```

## Deploy

```bash
arc-forge create contracts/ArcStreamVault.sol:ArcStreamVault \
  --rpc-url $ARC_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --constructor-args 0x3600000000000000000000000000000000000000
```

Plain Foundry equivalent (the docs recommend `arc-forge`, which handles Arc differences):

```bash
forge create contracts/ArcStreamVault.sol:ArcStreamVault \
  --rpc-url https://rpc.mainnet.arc.io \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --constructor-args 0x3600000000000000000000000000000000000000
```

Without `--broadcast`, `create` only simulates, so you can dry-run first. Save the printed `Deployed to:` address and `Transaction hash:`.

## After you deploy

1. Check it (read-only, no keys):
   ```bash
   bun run mainnet:check 0xYourVaultAddress
   ```
   All lines should say PASS.
2. Verify the source on the explorer:
   ```bash
   arc-forge verify-contract 0xYourVaultAddress contracts/ArcStreamVault.sol:ArcStreamVault \
     --chain-id 5042 \
     --verifier blockscout \
     --verifier-url https://explorer.arc.io/api/ \
     --constructor-args $(arc-cast abi-encode "constructor(address)" 0x3600000000000000000000000000000000000000)
   ```
3. Send the address and the transaction hash back in the chat. Arc Studio will record them in `src/contracts/mainnet.ts` and the explorer links (`https://explorer.arc.io/address/<address>` and `/tx/<hash>`). The running app stays on Arc Testnet unless you ask for a mainnet switch.
4. For the grant's "verified USDC transaction": make one small real escrow yourself from your own wallet, and keep the amounts small.

## Notes

- No admin, owner or upgrade keys exist in the contract. A mistake cannot be patched, only redeployed.
- Protected escrows cost about 380k gas per employer release or refund because of the PQ signature check.
- The contract has been through automated reviews and tests but not an independent professional audit.
