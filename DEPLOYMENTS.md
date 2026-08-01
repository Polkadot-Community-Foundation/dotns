# DotNS Deployments

Current deployment addresses and developer deployment notes for dotNS contracts.

## What this file is for

This file is the operational companion to the README. It explains how to run the local ETH-RPC adapter, how to deploy DotNS, where deployment manifests are written, and which addresses are currently live on the supported Paseo environments.

> For a short, do-this-in-order checklist (including how to target **any** Polkadot chain, not just the Paseo environments), see [`DEPLOYMENT_CHECKLIST.md`](./DEPLOYMENT_CHECKLIST.md).

## Prerequisites

You need:

- Docker with Compose support.
- Foundry, including forge and cast.
- Bun, because the package manifest wraps the deployment runner.
- A funded deployer key for the target network.
- A whitelist-operator address to receive whitelist-management permission after deployment.

The deployment runner uses a Foundry keystore account, not a long-lived plaintext private key. A plaintext private key is only needed for the first import of the deployer account into the local Foundry keystore.

## Local ETH-RPC adapter

Deploying to a revive-backed Paseo-style environment, and running fork tests against that chain state, requires a local ETH-RPC adapter. The repository includes a Docker Compose service named eth-rpc. It builds the revive ETH-RPC adapter image and exposes it on localhost port 8545.

The adapter is used instead of the public RPC directly because deployment and fork-test traffic is bursty. The public endpoint can rate-limit or stall under that pattern, which may drop in-flight transactions or invalidate fork-test assumptions. Unit, fuzz, and invariant tests still run in Foundry's in-process EVM; fork tests use the adapter.

Start the adapter:

```bash
docker compose up --build eth-rpc
```

In another terminal, confirm the adapter answers Ethereum JSON-RPC:

```bash
curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8545
```

The checked-in Compose file uses Previewnet as its example upstream:

```text
wss://previewnet.substrate.dev/asset-hub
```

Treat that URL as an example/default, not as a protocol constant. Developers can point the adapter at another compatible Asset Hub endpoint by changing the node RPC URL passed to the eth-rpc service, or by maintaining a local override for the Compose command.

The exposed local RPC is:

```text
http://localhost:8545
```

The Foundry RPC alias used by the deploy script defaults to the local adapter:

```text
paseo_local
```

## Multicall3

Fresh deployments include a generic Multicall3 contract. It is deployed for client, indexer, and tooling batching and is not dotNS-specific. The deployment script records it in the manifest as Multicall3 and the wire-up stage publishes it through the protocol registry under the MULTICALL3 key.

This is an arbitrary-target Multicall3 surface, matching the common mds1/multicall3 interface used by wallet and RPC tooling. It is permissionless: anyone can call it. Target contracts still enforce their own permissions and see Multicall3 as the caller during CALL-based write batching. Use it freely for read aggregation; use write aggregation only for flows where the target contract is meant to accept Multicall3 as msg.sender.

Its address is deterministic, not the canonical mds1 singleton. It is deployed through the dotNS CREATE3 factory under the label `Multicall3` (kind `contract`), so it lands at the same address on every chain that shares the same factory (see Deterministic addresses below), and that address is **not** the well-known `0xcA11...` deployment. Consumers must read the Multicall3 address from the protocol registry `MULTICALL3` key or from the deployment manifest, never hardcode `0xcA11...`.

## One-time deployer bootstrap

Copy the example environment file:

```bash
cp .env.example .env
```

Set these fields:

| Field | Required | Meaning |
| --- | --- | --- |
| ACCOUNT_NAME | optional | Foundry keystore account name. Defaults to dotns-deploy. |
| ACCOUNT_PASSWORD | yes on first import | Password used to import and unlock the Foundry keystore account. |
| PRIVATE_KEY | yes on first import | Hex deployer private key. This is imported into the Foundry keystore, then removed from disk when the deploy succeeds. |
| WHITELIST_OPERATOR | optional | Address granted whitelist-management permission after deployment. Defaults to the team operator in the example file. |
| RPC_URL | optional | Foundry RPC alias or full RPC URL. Defaults to paseo_local, which means the local adapter. |
| DEPLOYMENT_NETWORK | optional | Manifest subdirectory under deployments/. Set it to keep networks that share a chain id apart (see [Deployment manifests](#deployment-manifests)). Defaults to the chain-id mapping. |

The .env file is bootstrap input only. It is git-ignored. On a successful deployment the runner deletes it automatically. On failure the file is left in place so you can correct it and retry.

## Deploy locally through the adapter

Run the local-adapter deployment path:

```bash
bun run deploy:anvil
```

This command cleans and builds the project, then calls the staged deployment runner. Despite the name, this is not a local Anvil deployment; it is a deployment through the local revive ETH-RPC adapter.

## Build and test before deployment

Run a clean build before deploying:

```bash
forge clean
forge build
```

Run the full default Foundry test suite:

```bash
forge test -vvvvv
```

Run the non-fork suite when you do not have the adapter running:

```bash
forge test --no-match-path 'test/fork/**'
```

Run a targeted contract suite while iterating:

```bash
forge test --match-contract DotnsRegistrarControllerTest -vvvvv
forge test --match-contract DotnsNameEscrowTest -vvvvv
forge test --match-contract PopRulesTests -vvvvv
```

Run fork tests only after the ETH-RPC adapter is healthy on localhost port 8545:

```bash
docker compose up --build eth-rpc
forge test --match-path 'test/fork/**' -vvvvv
```

The expected test split is:

| Suite type | Environment | Purpose |
| --- | --- | --- |
| Unit tests | Foundry in-process EVM | Check isolated contract behaviour. |
| Fuzz tests | Foundry in-process EVM | Search input space around registration, transfer, escrow, and resolver invariants. |
| Invariant tests | Foundry in-process EVM | Exercise stateful flows such as escrow accounting and registrar lifecycle properties. |
| Fork tests | Local revive ETH-RPC adapter | Validate behaviour against live Paseo Asset Hub state and runtime assumptions. |

Do not use fork-test failures as a substitute for unit failures. If a fork test fails, first confirm the adapter is healthy and that the target network state has not drifted from the test assumptions.

## Deploy to testnet

Run the testnet deployment path:

```bash
bun run deploy:testnet
```

This calls the same deployment runner with a larger timeout. The runner forwards additional forge flags to every deployment stage.

You can call the runner directly when you need custom flags:

```bash
./scripts/deploy/run.sh '--slow --timeout 1000'
```

For scripted or CI use, provide secrets through the process environment instead of .env:

```bash
PRIVATE_KEY=0x... ACCOUNT_PASSWORD=... ./scripts/deploy/run.sh '--slow'
```

## Subsequent deployments

After the deployer key has been imported once, do not keep a private key in .env. Reuse the Foundry keystore account and provide only the password interactively or through the environment.

Typical subsequent run:

```bash
bun run deploy:testnet
```

If ACCOUNT_PASSWORD is not set and the process has a TTY, the runner prompts once for the keystore password and passes it to every stage.

## Deployment pipeline

The fresh-deploy pipeline is split across five stages:

| Stage | Script | Purpose |
| --- | --- | --- |
| Deploy core | scripts/deploy/DeployCore.s.sol | Foundational name-ownership layer: Multicall3, store factory, registrar, reverse resolver, and forward registry. |
| Deploy records | scripts/deploy/DeployRecords.s.sol | Per-name record layer: forward resolver, content resolver, and PopRules. |
| Deploy policy | scripts/deploy/DeployPolicy.s.sol | Commit-reveal controller and protocol registry. |
| Deploy Pop system | scripts/deploy/DeployPopSystem.s.sol | Proof-of-Personhood resolver and controller. |
| Wire deployments | scripts/deploy/WireDeployments.s.sol | Authorisation and registry wire-up plus end-to-end verification. This stage does not deploy proxies. |

Each stage is a separate forge script invocation and therefore a separate EVM simulation. This keeps OpenZeppelin's upgrade-safety validator from accumulating enough simulated state to exhaust the EVM during validation.

## Post-deployment verification

The final wire-up stage performs end-to-end verification for the deployed graph. After deployment, check the generated manifest and confirm the expected contracts are present for the target chain id.

At minimum, confirm:

- The protocol registry address is present.
- The registrar address is present.
- The public registrar controller address is present.
- The Multicall3 address is present.
- The Pop controller address is present.
- PopRules is present.
- The forward, reverse, content, and Pop resolvers are present.
- The escrow address is present.
- StoreFactory and both store beacons are present.
- The RootGatewayDispatcher is present on environments that use the root-dispatch path.

Then run the relevant tests again against the freshly deployed network assumptions:

```bash
forge test --match-path 'test/fork/**' -vvvvv
```

If the deployment was intended to update a public environment, update the address tables in this file from the deployment manifest in the same change that updates the generated deployment JSON.

## Whitelisting

The public registrar controller carries a whitelist for `registerReserved`. A whitelisted address can run the reserved registration path, which skips the Proof-of-Personhood pricing gate while still going through the normal commit-reveal and availability checks. See the [README economics section](./README.md#economics) for what whitelisting does and does not grant; this section covers the operator mechanics.

Authority comes in two levels. The owner holds the controller and grants or revokes the whitelist-operator role. A whitelist operator holds `WHITELIST_OPERATOR_ROLE` and can add or remove whitelisted addresses, but cannot grant the role on. A whitelisted address can call `registerReserved`. The role is held on the controller itself, so the owner rotates, grants, or revokes operators at any time without an upgrade. Granting the operator role and whitelisting an address are separate grants.

`WHITELIST_OPERATOR_ROLE` is a standard access-control role, so any number of addresses can hold it at once. The fresh-deploy pipeline grants it to the single `WHITELIST_OPERATOR` address described in [One-time deployer bootstrap](#one-time-deployer-bootstrap), in `_bootstrapWhitelistOperator` (present in both `scripts/deploy/WireDeployments.s.sol` and `scripts/deploy/DotnsDeployer.s.sol`):

```solidity
DotnsRegistrarController(addr.registrarController)
    .setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, whitelistOperator, true);
```

The `WHITELIST_OPERATOR` env carries one address. To seed more operators in the same deployment, add a `setRole` call per extra address in that helper, each address hardcoded or read from a further env var. The controller handle is `addr.registrarController` in WireDeployments and `deployment.registrarController` in DotnsDeployer:

```solidity
DotnsRegistrarController(addr.registrarController)
    .setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, anotherOperator, true);
```

After deployment, the owner grants further operators with `setRole`, which is owner-only and so must be broadcast from the owner key. Revoke with `false`:

```bash
ROLE=$(cast keccak "DOTNS_WHITELIST_OPERATOR_ROLE")
cast send "$CONTROLLER" "setRole(bytes32,address,bool)" "$ROLE" "$OPERATOR" true \
  --rpc-url "$RPC_URL" --account "$ACCOUNT_NAME"
```

To grant many operators, loop the same call over the addresses from the owner account:

```bash
ROLE=$(cast keccak "DOTNS_WHITELIST_OPERATOR_ROLE")
for OPERATOR in 0xOperator1 0xOperator2 0xOperator3; do
  cast send "$CONTROLLER" "setRole(bytes32,address,bool)" "$ROLE" "$OPERATOR" true \
    --rpc-url "$RPC_URL" --account "$ACCOUNT_NAME"
done
```

Whitelisting an address is the day-to-day operation, run by the owner or any operator. The dotNS SDK CLI exposes a whitelist command for this; run it from an account that holds the role (see the [dotns-sdk](https://github.com/paritytech/dotns-sdk) repository). The hosted dotNS app at [dotns.paseo.li](https://dotns.paseo.li) and [dotns.dot.li](https://dotns.dot.li) drives the same flow from its UI; see its docs section, built from the dotns-sdk UI packages. The equivalent direct call is `whiteListAddress(address who, bool whiteListStatus)`, again with `false` to remove:

```bash
cast send "$CONTROLLER" "whiteListAddress(address,bool)" "$ADDRESS" true \
  --rpc-url "$RPC_URL" --account "$ACCOUNT_NAME"
```

There is no batch entry point, so whitelisting many addresses is one call each. The SDK CLI applies a list in bulk; the dependency-free equivalent loops over the addresses from the role-holding account:

```bash
for ADDRESS in 0xAddress1 0xAddress2 0xAddress3; do
  cast send "$CONTROLLER" "whiteListAddress(address,bool)" "$ADDRESS" true \
    --rpc-url "$RPC_URL" --account "$ACCOUNT_NAME"
done
```

Both states are open view calls needing no authority: `isWhiteListed(address)` reports whether an address may call `registerReserved`, and `hasRole(WHITELIST_OPERATOR_ROLE, account)` reports whether an account holds the operator role. `$CONTROLLER` is the `DotnsRegistrarController` address for the target network, taken from the deployment manifest or the [Live addresses](#live-addresses) tables below, never hardcoded across networks.

## Deterministic addresses (CREATE3)

Every contract in the pipeline is deployed through a CREATE3 factory, so its address is a pure function of the factory address and a salt. It does not depend on the deployed bytecode, the constructor arguments, the deployer's nonce, or (for a proxy) the implementation behind it. This is what lets the same logical contract land at the same address on every chain, and lets an implementation be upgraded without moving its proxy.

The salt is derived in `BaseDeployer.s.sol`:

```text
salt = keccak256(abi.encodePacked(CREATE3_SALT_NAMESPACE, ":", label, ":", kind))
```

- `CREATE3_SALT_NAMESPACE` is `dotns.create3.v1`. It deliberately excludes the chain id so addresses match across chains.
- `label` is the manifest name for the contract, for example `DotnsRegistrar` or `Multicall3`.
- `kind` is `implementation` or `proxy` for a UUPS proxy pair, or `contract` for a non-upgradeable contract.

So a contract's address is fixed by exactly three inputs: the factory address, the salt namespace, and its label (plus kind). Keep all three stable and the address is stable. Bytecode, constructor arguments, and the deployer account do not affect it.

Choosing and changing addresses:

- To add a new contract with a stable cross-chain address, give it a unique `label` and deploy it through the BaseDeployer CREATE3 helpers (`_broadcastDeployUups` for a UUPS proxy, `_broadcastDeployCreate3` for a plain contract). Its address is then fixed for that label.
- To intentionally move the entire address set (a clean re-deploy that must not collide with the previous one), bump `CREATE3_SALT_NAMESPACE` (`v1` becomes `v2`). Every address shifts together.
- Do not reuse a `label` for a different contract. The wire stage and external tooling key off stable labels, so a reused label silently repoints them.

Two other manifest entries are not CREATE3-derived: `LabelStoreBeacon` and `UserStoreBeacon`. They are deployed inside the `StoreFactory` constructor (and owned by it, so the factory owner can upgrade store implementations), so their addresses are `keccak(StoreFactory, nonce)`. They stay put across resets while `StoreFactory`'s bytecode is unchanged, but a change to that constructor can move them. This is deliberate: only the core CREATE3 contracts are guaranteed stable, so do not treat the beacon addresses as network-stable, read them from the manifest or the factory.

The one address that is not CREATE3-derived is the CREATE3 factory itself: it bootstraps the scheme, so it cannot deploy itself. The first deploy stage deploys it directly and records it on the protocol registry under the `CREATE3_FACTORY` key; every later stage resolves it from there rather than from an environment variable. Because every other address is derived from the factory's address, the factory must sit at the same address on each chain for the rest of the set to match. Deploy it as the deployer's first transaction on a fresh account (or through a deterministic singleton deployer) so its nonce-derived address is identical across chains.

### Keeping the factory address stable across chain resets

The "first transaction on a fresh account" rule only holds while the deployer key stays pristine. In practice the same key also runs upgrades and other operations, so on a chain reset it is no longer at nonce 0 when the pipeline runs, the factory lands at a new address, and every downstream address shifts with it. Because only the factory is nonce-sensitive, the fix is to isolate just the factory onto a single-purpose key and have the pipeline reuse it.

The single command does both steps, feeding the factory address into the pipeline:

```bash
bun run deploy:all
```

It runs `deploy:factory` (from the dedicated `dotns-factory` key, which asserts nonce 0 and lands the factory at its deterministic address), then runs the pipeline with `CREATE3_FACTORY` set to that address so `DeployCore` reuses it. On every fresh chain this reproduces the same address set. The factory step is idempotent, so re-running is safe.

The two steps can also be run separately:

```bash
# 1. deploy (or confirm) the factory from the single-purpose key
ACCOUNT_NAME=dotns-factory RPC_URL=paseo bun run deploy:factory
# 2. run the pipeline reusing it (the shared pipeline/upgrade key can be at any nonce)
CREATE3_FACTORY=0xYourFactory bun run deploy
```

With `CREATE3_FACTORY` unset, `DeployCore` mints a fresh factory as before. On the next reset, `deploy:all` redeploys the factory from the same single-purpose key (nonce 0 again on the fresh genesis) to reproduce the same factory address.

## Deployment manifests

Every stage writes its output to a shared JSON manifest. Later stages read the addresses written by earlier stages from the same file.

The manifest folder defaults to a mapping from the current chain id:

| Chain id | Default manifest folder |
| ---: | --- |
| 420420422 | deployments/passethub-testnet |
| 420420417 | deployments/paseo-assethub |
| 420420420 | deployments/paseo-local |
| other | deployments/localhost |

Some environments cannot be told apart by chain id alone. A previewnet and a next environment reached through the same local ETH-RPC adapter both report 420420417, so the default mapping would write both to `deployments/paseo-assethub/420420417.json`, and each fresh deploy would overwrite the previous network's manifest.

Set `DEPLOYMENT_NETWORK` to name the subdirectory explicitly and keep each upstream's manifest separate:

```bash
DEPLOYMENT_NETWORK=paseo-previewnet bun run deploy
```

The deploy runner and every Solidity stage honour the same variable, so the bash-side manifest path and the on-chain stage output stay in step. When it is unset, the chain-id default above applies.

The manifest filename is the numeric chain id with a .json extension.

Examples:

```text
deployments/paseo-assethub/420420417.json
deployments/paseo-local/420420420.json
```

## Troubleshooting

If the adapter is not responding, confirm Docker is running and that port 8545 is free. The compose health check uses eth_chainId against http://localhost:8545.

If the deploy script says PRIVATE_KEY is required, the configured ACCOUNT_NAME has not yet been imported into the Foundry keystore. Populate .env once, or provide PRIVATE_KEY and ACCOUNT_PASSWORD through the shell environment.

If the deploy script fails after importing the key, .env is intentionally left in place. Correct the failed field or network issue and rerun the same command.

If the deploy script succeeds, .env should be gone. Future runs should use the keystore account and should not require the deployer private key.

If a stage fails after writing partial addresses, inspect the relevant deployment manifest before retrying. Later stages consume whatever earlier stages wrote, so stale manifests can produce confusing wire-up errors.

## Live addresses

### Paseo Asset Hub Previewnet

**DotnsProtocolRegistry**

```text
0x984F17a9077808F4B7e127F76806A1D59546B5B6
```

**Multicall3**

```text
0x758F88C7761FCD4742f9471448c2209a7e859280
```

**DotnsRegistrar**

```text
0x061273AeF34e8ab9Ca08E199d7440E2639Fc2088
```

**DotnsRegistry**

```text
0x5622CA75C75726Da13ae46C69127C07c87538633
```

**DotnsRegistrarController**

```text
0xC0c21ca6302884572E61d69D5bf3E271Acf39B23
```

**DotnsPopController**

```text
0xae2c63b921Bc9DC30C149A8FA462fd3efA53D1F4
```

**RootGatewayDispatcher**

```text
0xDf919455Fb357c173d6C3143dB1B7aFb9eA61324
```

**PopRules**

```text
0xF209a15e8a10D208bb4d3e3c56D9EB73a5934C26
```

**DotnsResolver**

```text
0x823f39E7a4126669be53211FFbCF27e55b3274C6
```

**DotnsReverseResolver**

```text
0xA347059298aA171b3E744538F7043e9AAaAa95E0
```

**DotnsContentResolver**

```text
0xBD003d5Dd04E68aC60d529a46AEfBdEf8941868C
```

**DotnsPopResolver**

```text
0xeD11Bb5064fAAcb0A91e52dac2272E89856F2F6a
```

**DotnsNameEscrow**

```text
0xb7E39199f13aCf7e90cCf67b980aC3ef0E2C4Fbe
```

**StoreFactory**

```text
0x4BEFaB5de968183524b1eBd2FAec9C68Cdc696Fd
```

**LabelStoreBeacon**

```text
0x11f324597d850d626d6406713808Ed854dA00a6b
```

**UserStoreBeacon**

```text
0xaC2209aFc366505d10Fd27d27030EB8C5E54874e
```

### Paseo Asset Hub Next V2

**DotnsProtocolRegistry**

```text
0x8F28419f4E32Bb0aA02e156A0543Ff253f126D7D
```

**Multicall3**

```text
0xFc430CcCdb9335C1907fc72e93eb1f48e847319C
```

**DotnsRegistrar**

```text
0xf7Ad3F44F316C73E4a2b46b1ed48d376bCc9E639
```

**DotnsRegistry**

```text
0xa1b2b939E82b2ecE55Bd8a0E283818BfC1CA6CDc
```

**DotnsRegistrarController**

```text
0x674b705268DAE369F0a7BE9cbaCDb928b8BA38C2
```

**DotnsPopController**

```text
0x1c858C31497a7715C0D56A11208feB6b74FaB2aB
```

**RootGatewayDispatcher**

```text
0xd3F059FA65dA566B294b5d755a06054d4bE7ce7C
```

**PopRules**

```text
0x4909bFb3f4Fd86244abD6430fDfA0Ce5C91aD0c4
```

**DotnsResolver**

```text
0xA8988eA083174ea94Ed1D686f0F073a10f65598D
```

**DotnsReverseResolver**

```text
0x259B9D8199c29d2EF132264ad05f8F74F3115A2E
```

**DotnsContentResolver**

```text
0x8A26480b0B5Df3d4D9b95adc24a5Ecb33A5b8F64
```

**DotnsPopResolver**

```text
0xC9D511Eb80fD8B745DC5Be59aCF5d700271bC01e
```

**DotnsNameEscrow**

```text
0x2Cb9899d91Ee575E8917958723F5E941b1BcC6A1
```

**StoreFactory**

```text
0x692047C1477a017F287488E1c85F96Ca28C23fD8
```

**LabelStoreBeacon**

```text
0x86ff9CE56C86bC3DfcaA7E316FB0Dd816e9fA2df
```

**UserStoreBeacon**

```text
0x6a7a938f72D39f949ee484a78c4C500514E2cb69
```
