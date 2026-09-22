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

Fresh deployments include a generic Multicall3 contract. It is deployed for client, indexer, and tooling batching and is not dotNS-specific. The deployment script records it in the manifest as Multicall3. It is deliberately **not** published through the protocol registry: registry membership is a trust signal protocol contracts read, and an arbitrary-target call forwarder must never carry it.

This is an arbitrary-target Multicall3 surface, matching the common mds1/multicall3 interface used by wallet and RPC tooling. It is permissionless: anyone can call it. Target contracts still enforce their own permissions and see Multicall3 as the caller during CALL-based write batching. Use it freely for read aggregation; use write aggregation only for flows where the target contract is meant to accept Multicall3 as msg.sender.

Its address is deterministic, not the canonical mds1 singleton. It is deployed through the dotNS CREATE3 factory under the label `Multicall3` (kind `contract`), so it lands at the same address on every chain that shares the same factory (see Deterministic addresses below), and that address is **not** the well-known `0xcA11...` deployment. Consumers must read the Multicall3 address from the deployment manifest, never hardcode `0xcA11...`. Deployments made before the `MULTICALL3` key was dropped still carry it in their registry; that entry is retained for compatibility and should not be relied on for new integrations.

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
| RPC_URL | optional | Foundry RPC alias or full RPC URL. Defaults to paseo_local, which means the local adapter. |
| DEPLOYMENT_NETWORK | optional | Manifest subdirectory under deployments/. Set it to keep networks that share a chain id apart (see [Deployment manifests](#deployment-manifests)). Defaults to the chain-id mapping. `DOTNS_DEPLOYMENT_FOLDER` is accepted as an alias. |

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

## Upgrading a proxy that gained a new configuration value

An upgrade that adds a governance-tunable storage value must seed it in the **same transaction** as the implementation swap. A bare `upgradeTo` leaves the new slot at zero, and a proxy running with an unseeded policy value is a live misconfiguration, not a pending chore.

UUPS supports this directly: `upgradeToAndCall` performs the post-upgrade call as a delegatecall from the proxy context, so `msg.sender` is preserved and an `onlyOwner` setter is callable as part of the upgrade.

### DotnsNameEscrow: `redeemWindow`

The escrow's redeem window is the period after a `release` in which only the previous holder may act — they alone may `redeem` the name back, and `available` reports `false` so nobody wastes a commitment on it. Once it elapses, `reclaim` is permissionless. It is a separate value from `cooldown` and defaults to `ESCROW_REDEEM_WINDOW` (1 day) on a fresh deploy.

Upgrade an existing escrow proxy like this, not with a bare `upgradeTo`:

```bash
# 1 day, matching the ESCROW_REDEEM_WINDOW deploy constant
cast send "$ESCROW_PROXY" \
  'upgradeToAndCall(address,bytes)' \
  "$NEW_IMPL" \
  "$(cast calldata 'updateRedeemWindow(uint256)' 86400)" \
  --account "$DEPLOYER" --rpc-url "$RPC_URL"
```

Verify before considering the upgrade done:

```bash
cast call "$ESCROW_PROXY" 'redeemWindow()(uint256)' --rpc-url "$RPC_URL"   # expect 86400
```

If the window is left at zero, `release` reverts with `RedeemWindowNotConfigured` for **every** name on that deployment. That is deliberate: the alternative would be stamping `redeemableUntil` at the current timestamp, which silently opens permissionless reclaim the instant a name is released and hands the name to whoever is watching. A loud failure on `release` is recoverable with one owner transaction; a silent one is not.

To recover a proxy already upgraded without seeding, call the setter directly — no second upgrade is needed:

```bash
cast send "$ESCROW_PROXY" 'updateRedeemWindow(uint256)' 86400 \
  --account "$DEPLOYER" --rpc-url "$RPC_URL"
```

Bounds: at least `MIN_REDEEM_WINDOW` (1 day) and at most `MAX_REDEEM_WINDOW` (30 days). Changing the window later affects only releases recorded after the change; positions already released keep the `redeemableUntil` snapshot taken at their release time.

### The window does not apply to names already in escrow

Seeding `redeemWindow` covers every release *after* the upgrade. It does nothing for names already sitting in escrow when the upgrade lands, and operators should understand what happens to those.

A position released under the old contract has no `redeemableUntil` — the field reads as zero from previously unused padding. So the moment the upgrade lands:

- the name is **immediately reclaimable by anyone**, with no redeem grace at all
- `available` reports it registrable straight away
- its previous holder **cannot** `redeem` it, because the redeem window is already behind them

No value is lost: reclaim settles the deposit onto the previous holder's pull-payment balance, so they are made whole whether or not they ever withdrew. And these are names that were **stuck** before the upgrade, so becoming claimable is the fix working. But the previous holder gets no chance to change their mind, which is the one guarantee the upgrade cannot apply retroactively.

Enumerate the affected set before upgrading, so the outcome is a decision rather than a surprise:

```bash
cast call "$ESCROW_PROXY" 'releasedTokenCount()(uint256)' --rpc-url "$RPC_URL"
cast call "$ESCROW_PROXY" 'releasedTokens(uint256,uint256)(uint256[])' 0 200 --rpc-url "$RPC_URL"
```

If that set is non-empty and any of it matters, the options are to let the holders reclaim or withdraw before the upgrade, or to notify them that the grace period will not cover their name.

## Deployment pipeline

The fresh-deploy pipeline is split across five stages:

| Stage | Script | Purpose |
| --- | --- | --- |
| Deploy core | scripts/deploy/DeployCore.s.sol | Foundational name-ownership layer: Multicall3, store factory, registrar, reverse resolver, and forward registry. |
| Deploy records | scripts/deploy/DeployRecords.s.sol | Per-name record layer: forward resolver, content resolver, and PopRules. |
| Deploy policy | scripts/deploy/DeployPolicy.s.sol | Registration policy layer: name escrow and commit-reveal controller. |
| Deploy Pop system | scripts/deploy/DeployPopSystem.s.sol | Proof-of-Personhood resolver and controller. |
| Wire deployments | scripts/deploy/WireDeployments.s.sol | Authorisation and registry wire-up plus end-to-end verification. This stage does not deploy proxies. |

Each stage is a separate forge script invocation and therefore a separate EVM simulation. This keeps OpenZeppelin's upgrade-safety validator from accumulating enough simulated state to exhaust the EVM during validation.

## Post-deployment verification

The final wire-up stage performs end-to-end verification for the deployed graph. After deployment, check the generated manifest and confirm the expected contracts are present for the target chain id.

At minimum, confirm:

- The protocol registry address is present.
- The registrar address is present.
- The public registrar controller address is present.
- The Multicall3 address is present in the manifest. It is not a protocol registry key.
- The Pop controller address is present.
- PopRules is present.
- The forward, reverse, content, and Pop resolvers are present.
- The escrow address is present.
- StoreFactory and both store beacons are present.
- The escrow's redeem window is non-zero. A zero leaves `release` reverting with `RedeemWindowNotConfigured` for every name on the deployment, so a holder who releases a name by accident has no chance to redeem it back. Any value the setter accepted is already at least `MIN_REDEEM_WINDOW` (1 day), so this check is only ever confirming that the window was configured at all, which is exactly what a proxy upgraded without seeding it would fail.

```bash
cast call "$ESCROW_PROXY" 'redeemWindow()(uint256)' --rpc-url "$RPC_URL"   # expect 86400 at launch
```

Then run the relevant tests again against the freshly deployed network assumptions:

```bash
forge test --match-path 'test/fork/**' -vvvvv
```

If the deployment was intended to update a public environment, update the address tables in this file from the deployment manifest in the same change that updates the generated deployment JSON.

### Network manifests and the expected set

`deployments/<network>/<chainId>.json` is a **network record**: what is deployed on that live network right now. It is updated only by a real deploy or migration on that network, never by a code change. Everything that answers for reality reads these files: releases copy their addresses verbatim, and pointing tooling or the wire stage at an address with nothing behind it breaks whatever reads it.

`deployments/expected.json` is the **expected set**: the addresses a fresh deploy of the current revision lands through the pinned CREATE3 factory. It is a property of the code, not of any network; the CI deploy job and `scripts/genesis/build-genesis.sh` verify against it, and releases never publish it.

The expected set can legitimately disagree with a network manifest: after a code change moves an address, the expected set carries the new address while every network manifest keeps the old one until that network actually redeploys. The difference between them is the migration backlog, readable as a diff, and it is resolved per network by the event that relocates the contract: a wipe-and-redeploy on a test network, a deliberate migration on one that never wipes.

Before deploying to a live network, diff its manifest against `deployments/expected.json`. If any address diverges, run the pipeline against that network only as that planned wipe or migration: run outside it, the pipeline deploys the diverged contracts beside the live ones with empty state and repoints their registry keys, stranding any state behind the old addresses. After the planned deploy, commit the manifest it writes and update the address tables in this file in the same change.

## Name grants (whitelisting)

Reserved registration is gated on `DotnsNameWhitelist`. A grant binds one label to one beneficiary address and is single use: `registerReserved` requires a grant naming `registration.owner`, spends it on the mint, and refuses a second attempt. See the [README economics section](./README.md#economics) for what a grant does and does not confer; this section covers the mechanics.

**Every admin action on the whitelist is a substrate Root dispatch.** Granting, revoking, accepting, rejecting, reserving, setting the request window and retuning the caps all require it. No signed account can do any of them, the contract owner included: the owner's authority is deployment and upgrade, not allocation. A signed call reverts with `NotGovernance`. There is no operator role and no address allowlist.

That is the point of the design. As a security measure, no single key can grant a name; a grant costs a referendum, or on a test network a sudo-dispatched Root call.

Two owner-level routes reach the same outcome and are **not** closed by this. `DotnsProtocolRegistry.set` is `onlyOwner`, so the owner can point the `nameWhitelist` key at a contract whose `isGrantedTo` returns true for everything. `DotnsRegistrar.addController` is `onlyOwner`, and a controller can mint any available name directly, without the whitelist at all. Treat the guarantee here as covering the whitelist's own admin surface, not the protocol as a whole, until upgrade authority and deploy-time ownership are settled.

The controller carries no roles either. It reads grants and consumes them, so `setRole` on the controller reverts with `UnsupportedRole`.

### Dispatching a grant

The dispatch is a Substrate extrinsic with the contract call nested inside it:

```
Root origin
  └─ Revive.call { dest: <DotnsNameWhitelist H160>, value: 0, data: <EVM calldata> }
       └─ grantName(string,address)
```

`cast` can be used for the innermost layer to encode `data`:

```bash
# grant one label to one beneficiary
cast calldata "grantName(string,address)" "$LABEL" "$ADDRESS"

# grant several labels to one beneficiary, up to maxGrantBatch
cast calldata "grantNames(string[],address)" '["alpha01","beta02"]' "$ADDRESS"

# release an unspent grant
cast calldata "revokeName(string)" "$LABEL"
```

Building the `Revive.call` around that hex and dispatching it as Root is done on the Substrate side. Wrap it in `Sudo.sudo` on a test network; put it up as a referendum on a production one. Both produce the same Root origin the contract checks, so the same `data` works either way.

The gas and storage-deposit limits belong to the `Revive.call` extrinsic rather than the contract call. Dry-run the call to size them rather than guessing, as an underestimate fails the whole dispatch.

### Reading state

Both views are open and need no authority:

```bash
cast call "$WHITELIST" "isGrantedTo(string,address)(bool)" "$LABEL" "$ADDRESS"
cast call "$WHITELIST" "statusOf(string)(uint8)" "$LABEL"
```

A grant that has been spent reads `false`, so `isGrantedTo` also distinguishes an unused grant from a consumed one. `$WHITELIST` is the `DotnsNameWhitelist` address for the target network, read from the protocol registry under the `nameWhitelist` key or taken from the [deployment manifest](#addresses), never hardcoded across networks.

### Configuration is Root too

`setWindow`, `setMaxClaimants`, `setMaxReasonBytes` and `setMaxGrantBatch` are on the same gate, so the deploy cannot configure the whitelist and the values `initialize` sets are what a fresh network starts with. Changing any of them later costs a governance action, so check the defaults in `DotnsConstants` are the ones you want at launch.

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

Two other manifest entries are not CREATE3-derived: `LabelStoreBeacon` and `UserStoreBeacon`. They are deployed inside the `StoreFactory` initialiser, which runs by delegatecall from the proxy constructor, so they are owned by the `StoreFactory` proxy and their addresses are `keccak(StoreFactory proxy, nonce)`. Owning them from the proxy is what keeps store-implementation upgrades available across a factory upgrade: the beacons answer to an address whose logic can be replaced, rather than to the code deployed on day one. They stay put across resets while the initialiser is unchanged, but a change to it can move them. This is deliberate: only the core CREATE3 contracts are guaranteed stable, so do not treat the beacon addresses as network-stable, read them from the manifest or the factory.

The one address that is not CREATE3-derived is the CREATE3 factory itself: it bootstraps the scheme, so it cannot deploy itself. The first deploy stage deploys it directly and records it on the protocol registry under the `CREATE3_FACTORY` key; every later stage resolves it from there rather than from an environment variable. Because every other address is derived from the factory's address, the factory must sit at the same address on each chain for the rest of the set to match. Deploy it as the deployer's first transaction on a fresh account (or through a deterministic singleton deployer) so its nonce-derived address is identical across chains.

### Occupied addresses, and what a resume will adopt

A CREATE3 address can already hold code when the pipeline reaches it. Either the run is a resume and that code is its own earlier deployment, or someone else put it there: `Create3Factory.deploy` is permissionless and the salts above are a pure function of public constants, so any dotNS address can be occupied in advance by anyone who reads them off a live deployment.

The pipeline adopts an occupant only when its runtime code is what this run would have deployed, and fails the whole stage otherwise. It never adopts on faith, and it never silently writes a foreign contract into the protocol registry or the manifest.

Matching works in two steps, in `BaseDeployer._requireExpectedCode`:

- An exact codehash match against the artefact is accepted immediately. This covers every contract without constructor-set immutables, `ERC1967Proxy` included.
- Otherwise the artefact carries immutables, whose values are baked into runtime code, so no fixed codehash exists to compare against. The pipeline deploys the artefact twice locally, with this run's constructor arguments, and compares the occupant against those references. Bytes that agree across both references are what those arguments produce and must match. Bytes that differ between them are address-derived and vary on every honest deploy, so they are skipped.

The reference copies are throwaway and are deployed with broadcasting paused, so they are never sent as transactions.

That second step is what rejects a genuine artefact deployed against someone else's constructor arguments: a real `DotnsPopLens` pointed at an attacker's protocol registry has the right length and shape, and differs only in the values its constructor wrote.

**What the bytecode check cannot cover.** Immutables whose values are address-derived are indistinguishable between an honest deploy and any other, because they legitimately differ every time. Only `UUPSUpgradeable.__self` is in that class now, and every UUPS implementation carries it, so the masking handles it uniformly. `StoreFactory` used to be the case that mattered, because it minted its own beacons into immutables; behind a proxy it holds the beacons and `protocolRegistry` in storage and carries no immutables of its own, so its implementation compares exactly. Immutables set from a constructor argument stay inside the comparison, which is what rejects an artefact built against someone else's addresses: `DotnsPopLens.protocolRegistry` and `DotnsFlatPricing.deposit` are the two that remain. An owner is never covered here, since `Ownable` keeps it in storage rather than runtime code; the wire stage's `owner()` assertions cover it instead.

The beacons are checked separately. The verification stage asserts that each beacon's code is the `UpgradeableBeacon` artefact, that the factory owns it, and that its implementation is the `LabelStore` or `UserStore` artefact this release builds. None of the three contracts carries immutables, so each comparison is exact.

The beacon's own code is pinned before the other two are read, because `owner()` and `implementation()` are views: a bespoke contract can answer them correctly once and differently afterwards. Ownership is asserted because `upgradeLabelStoreImplementation` is `onlyOwner` on the factory, so a beacon owned by anything else leaves every store on the network following an implementation the verified owner cannot rotate.

**Recovering a burned address.** An occupant that fails the check cannot be evicted: CREATE3 slots are single use. Set `DOTNS_SALT_VERSION` to a value above `1` to move the whole set onto fresh addresses; the salt then gains a `:<version>` suffix. This is a recovery lever, not routine configuration, and every address moves together.

**A note for anyone adding an initialiser.** Proxies are initialised inside the `ERC1967Proxy` constructor, so there is no window in which a deployed proxy is uninitialised. One consequence is easy to trip over: the owner is now an explicit argument rather than the caller, so an initialiser must not call its own `onlyOwner` setters, which would reject the deployer mid-initialisation. Because the initialiser runs during construction, such a revert surfaces as CREATE3's opaque `DeploymentFailed()` rather than the underlying error. Seed values through internal helpers instead.

### Keeping the factory address stable across chain resets

The "first transaction on a fresh account" rule only holds while the deployer key stays pristine. In practice the same key also runs upgrades and other operations, so on a chain reset it is no longer at nonce 0 when the pipeline runs, the factory lands at a new address, and every downstream address shifts with it. Because only the factory is nonce-sensitive, the fix is to isolate just the factory onto a single-purpose key and have the pipeline reuse it.

The single command does both steps, feeding the factory address into the pipeline:

```bash
bun run deploy:all
```

It runs `deploy:factory` (from the dedicated `dotns-factory` key, which asserts nonce 0 and lands the factory at its deterministic address), then runs the pipeline with `CREATE3_FACTORY` set to that address so `DeployCore` reuses it. On every fresh chain this reproduces the same address set.

The whole pipeline is idempotent, so a re-run resumes an interrupted deploy. Each stage adopts any contract already present at its deterministic address and skips re-initialising an adopted proxy, so rerunning the same command deploys only what is missing and leaves everything already deployed untouched. This is the recovery path when the adapter stalls a transaction part way through.

Idempotent is not the same as always succeeding. Both adoption and the final verification compare what is on chain against the artefacts of the release being run, so a chain that has moved away from them fails rather than reporting a clean no-op. Rotating a store implementation through `StoreFactory.upgradeLabelStoreImplementation` is the case to expect: verification then fails on the beacon implementation until the release being run is the one that was rotated to. Re-running a stage against a chain that is ahead of, or diverged from, the checked-out release is therefore not a safe no-op.

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
| 420420417 | deployments/pcf-devnet |
| 420420420 | deployments/paseo-local |
| other | deployments/localhost |

Some environments cannot be told apart by chain id alone. A previewnet and a next environment reached through the same local ETH-RPC adapter both report 420420417, so the default mapping would write both to `deployments/pcf-devnet/420420417.json`, and each fresh deploy would overwrite the previous network's manifest.

Set `DEPLOYMENT_NETWORK` to name the subdirectory explicitly and keep each upstream's manifest separate:

```bash
DEPLOYMENT_NETWORK=paseo-previewnet bun run deploy
```

The deploy runner and every Solidity stage honour the same variable, so the bash-side manifest path and the on-chain stage output stay in step. When it is unset, the chain-id default above applies.

The manifest filename is the numeric chain id with a .json extension.

Examples:

```text
deployments/pcf-devnet/420420417.json
deployments/paseo-local/420420420.json
```

A manifest holds exactly one address per contract, the current one. Each deploy overwrites the entries it produces, so the file always describes the latest deployment for that network and never a history of them. Previous address sets exist only in this repository's git history. Nothing else is in there either: no implementation addresses behind the UUPS proxies, and no record of which commit was deployed.

## Production (Polkadot Asset Hub)

Production is deployed by `.github/workflows/deploy-production.yml` (manual dispatch) from a Cloud KMS secp256k1 key. The workflow has two modes: `devnet` (default; environment `devnet`, key `contract-deployer-devnet`, devnet Asset Hub) and `live` (environment `production`, key `contract-deployer`, Polkadot Asset Hub). Devnet comes first: it proves HSM signing and that the contracts deploy on a real chain; production comes last. There is no fork mode in CI (no chopsticks, no rehearsal key); rehearsals run locally with `scripts/deploy/rehearse-fork.sh`. On production the same key later deploys AccountDataStore, so DotNS must go first: its CREATE3 factory has to be the key's nonce-0 transaction. The deployer only pays and writes; ownership ends with the `dotns-owner` pure proxy.

Inputs: `mode` (`devnet` default or `live`), `new_owner` (the H160 of `dotns-owner`), `steps` (`all` default; see "Steps" below), `factory_nonce` (standalone steps only, default `0`), `sweep_to` (optional; required for `steps=sweep`), `confirm` (`deploy dotns to polkadot`, required for `live` whatever the step; `live` must also be dispatched from a release tag, e.g. `v0.8.0-pcf.1`, so the deployed commit keeps a permanent name), `resume` (default false; `all`/`deploy` only, see "Transient RPC failures and resume" below). Endpoints: `SUBSTRATE_WS_URL` variable, else `wss://asset-hub-paseo-rpc.n.dwellir.com` (devnet) or `wss://polkadot-asset-hub-rpc.polkadot.io` (live). Devnet uses the public ETH-RPC (`ETH_RPC_URL` variable, else `https://eth-rpc-testnet.polkadot.io`). Polkadot Asset Hub has no public ETH-RPC, so in `live` the job runs the eth-rpc adapter itself against `SUBSTRATE_WS_URL`: the pinned `docker.io/parity/eth-rpc:v1.24.2` image (pallet-revive-eth-rpc 0.21.0, pinned by digest in the workflow) unless the `ETH_RPC_IMAGE` variable names another.

The job runs these scripts, all from the repo root (which of them depends on `steps`):

| Step | Script | What it does |
| --- | --- | --- |
| Rebuild manifest | `scripts/deploy/rebuild-manifest.sh` | Standalone steps only (`handover`, `verify`, `sweep`). Read-only: rebuilds the set from the deployer and `factory_nonce` (`expected-set.sh`), requires every address to hold code that is the artefact the pipeline deploys there (`expected-code.py --ignore-metadata`), then writes it to `deployments/<network>/<chain id>.json`, or, when that file is committed, requires it to equal the rebuilt set. |
| Preflight | `scripts/deploy/preflight.sh` | Refuses unless: chain id 420420417 (`devnet`) or 420420419 (`live`), sender nonce equal in the eth and Substrate views (and exactly 0 in `live`), free balance ≥ `MIN_BALANCE_DOT` (40 DOT; 50 PAS on devnet Asset Hub), `NEW_OWNER` set, not zero, without code, and no address of the expected set has code. Prints `FACTORY_NONCE=<sender nonce>`, which the job exports for the deploy. With `DEPLOY_RESUME=1` the nonce and occupancy rules change as described below. |
| Deploy | `scripts/deploy/deployall.sh` | Factory (at `FACTORY_NONCE`), then the five stages, with `DOTNS_TLD=dot`, `DOTNS_RELEASE_TAG=0.8.0`. One key for factory and pipeline. Each stage gets `DEPLOY_STAGE_ATTEMPTS` (3) attempts. |
| Handover | `scripts/deploy/handover.sh` | `transferOwnership(NEW_OWNER)` on every manifest contract the sender owns, `DotnsProtocolRegistry` last, `owner()` asserted after each. Plans first and refuses unless the plan covers exactly `EXPECTED_HANDOVER_COUNT` (14) contracts; contracts already owned by `NEW_OWNER` count as done, so a re-run resumes, and a set already handed over in full exits 0 without sending. Never renounces. |
| Verify | `scripts/deploy/verify-production.sh` | Read-only: manifest equals the expected set derived from its own `Create3Factory` entry (and, with `FACTORY_NONCE` set, that factory is the deployer's CREATE at it), code at every address, the 14 owners equal `EXPECTED_OWNER` (`NEW_OWNER` by default; the deployer for `steps=deploy`), beacons owned by `StoreFactory`, then `VerifyProduction.s.sol` re-runs the `WireDeployments` checks and asserts the release and the TLD. |
| Sweep | `scripts/deploy/sweep.sh` | Refuses while the deployer still owns any of the 14 owned contracts (hand over first). Sends the leftover (minus the existential deposit and the max fee) to `SWEEP_TO`, only if `SWEEP_TO` is mapped (`Revive.OriginalAccount`). The same key deploys AccountDataStore after DotNS, so sweep only after that deploy (leave `sweep_to` empty on the DotNS run). An eth transfer to an unmapped H160 lands on its `0xEE` fallback account, which nobody controls for a Substrate-derived H160. |

Outputs: `deployments/polkadot/420420419.json` (live) or `deployments/pcf-devnet-ci/420420417.json` (devnet), the broadcast files, the logs and a cost summary (spend per step, wall-clock time per step) from the deployer's Substrate `System.Account` balance, kept 90 days as a workflow artifact. The job log streams the deploy as it runs: the stage and attempt headers, the estimates and errors from the forge output (the full `-vvvvv` output stays in `logs/deploy.log`), every landed transaction read from the forge broadcast checkpoints, and a heartbeat every 30 s with the deployer's nonce and balance (`scripts/deploy/progress.py`). forge's own receipt lines never reach a job log: it prints them through a progress bar that only draws on a terminal.

**Steps.** In production the deploy, the handover and the sweep are separate dispatches. `steps` selects one:

| `steps` | Runs | Notes |
| --- | --- | --- |
| `all` | preflight, deploy, handover, verify, sweep if `sweep_to` is set | The devnet flow. |
| `deploy` | preflight, deploy, verify | Verify expects the deployer as owner of the 14 contracts (`EXPECTED_OWNER`); no handover. |
| `handover` | rebuild manifest, handover, verify | Transfers only what the deployer still owns; a set already handed over in full is a success with nothing sent. |
| `verify` | rebuild manifest, verify | Read-only. |
| `sweep` | rebuild manifest, sweep | Refuses while the deployer owns any of the 14; `sweep_to` required and mapped. |

Order in production: `deploy` → `handover` → AccountDataStore (its own repo, same key) → `sweep`. Between `deploy` and `handover` the hot key owns every contract: dispatch the handover as soon as the deploy's verify is green and keep that gap short.

The standalone steps have no manifest from the deploy run (it is only a workflow artifact), so they rebuild the set: `factory_nonce` is the key nonce the factory was deployed at (the preflight printed it and the summary shows it; `0` on Polkadot Asset Hub, where it is the only value accepted), and the set follows from the factory as in `expected-set.sh`. Nothing runs until every address of the rebuilt set holds the pipeline's code (compiler metadata masked, since that hash covers the build environment), and a manifest committed at `deployments/<network>/<chain id>.json` must equal the rebuilt set, else the step refuses. `all` and `deploy` ignore `factory_nonce`: the preflight takes the nonce from the key.

**Signer.** Every script takes `DEPLOY_SIGNER`: `keystore` (default, the Foundry keystore flow above) or `gcp` (`forge`/`cast --gcp` with `GCP_PROJECT_ID`, `GCP_LOCATION`, `GCP_KEY_RING`, `GCP_KEY_NAME`, `GCP_KEY_VERSION`; the sender is read from the key).

**Mode/key/chain guard.** A fork keeps its origin chain's genesis and chain id, so a signature made on it is valid on the live chain. Every KMS path (and preflight, handover, sweep with any signer) requires `DEPLOY_MODE` and checks the chain before touching the key. With `DEPLOY_SIGNER=gcp`: a `*-devnet` key signs only in `devnet`, on chain id 420420417 that is not a chopsticks fork (`SUBSTRATE_RPC_URL` does not serve `dev_newBlock`); `contract-deployer` signs only in `live`, on chain id 420420419 that is not a fork; every other key name, and any KMS key in `fork`, is refused. The keystore signer is accepted in `devnet` and `fork` (a chopsticks fork of either Asset Hub) and refused in `live`. `substrate.py same-chain` then proves the ETH-RPC serves the chain behind `SUBSTRATE_RPC_URL`.

**Devnet run (`mode=devnet`).** The job runs in the `devnet` environment (its variables carry the devnet `GCP_*` settings and `GCP_WORKLOAD_IDENTITY_PROVIDER`/`GCP_SERVICE_ACCOUNT`) and signs with `contract-deployer-devnet`. The manifest goes to `deployments/pcf-devnet-ci/420420417.json`, so the real devnet set (`deployments/pcf-devnet/`) is never touched; `DOTNS_TLD=dot` is safe because the run lands a separate registry under a fresh factory address that nothing on devnet points at. No `confirm` is needed. Fund the key's fallback account with at least 50 PAS (55 recommended): the devnet gas price is 1e12 wei against 8e11 on Polkadot, and 40 DOT × 1.25 covers the worst case where every cost scales with it (the earlier devnet DotNS deploy spent ~32 PAS).

**Used keys.** On devnet the key may be at any nonce: preflight records the current nonce as `FACTORY_NONCE`, the factory lands at that nonce's CREATE address and the rest of the set follows from it, so the same key can deploy DotNS again after other transactions. Only the live run keeps the nonce-0 rule (the AccountDataStore deploy depends on it). A second live run therefore needs a new version of `contract-deployer` (`GCP_KEY_VERSION` on the `production` environment).

**Transient RPC failures and resume.** A public ETH-RPC answering one request with a 502 aborted a whole devnet run: forge retries a request only on HTTP 429/503 (alloy's retry policy; `--fork-retries`/`--fork-retry-backoff` change the count for the simulation provider only, and `--retries`/`--delay` are Etherscan verification flags), so a 502 or a refused connection fails the `forge script` stage. Two layers handle this, both resting on the stages being idempotent.

*Stage retry* (`scripts/deploy/_retry.sh`, used by `run.sh` and `factory.sh`): each stage, and the factory deploy, gets `DEPLOY_STAGE_ATTEMPTS` (default 3) attempts. A failed attempt restores the manifest to its pre-stage state, backs off (10 s, then 30 s), waits until the RPC answers `eth_chainId` again (up to `DEPLOY_RPC_WAIT_SECONDS`, 600) plus `DEPLOY_STAGE_SETTLE_SECONDS` (12, two blocks, so a transaction in flight when the stage died has landed), and re-runs the stage. The log names every attempt. The run fails only after the last attempt.

The re-run happens only when the failed attempt broadcast nothing (the CI case: a 502 on the stage's first request, before any transaction) or everything it broadcast was confirmed (`broadcast/<Stage>.s.sol/<chain id>/run-latest.json` absent, empty, or with a receipt per transaction). An attempt that died with transactions unconfirmed is not re-run and the run stops with the recovery printed: `BaseDeployer._broadcastDeployUups` deploys a UUPS implementation and its proxy as two transactions and refuses to adopt an implementation whose proxy is absent (`scripts/deploy/BaseDeployer.s.sol:290-297`, "implementation address already occupied while its proxy is absent. Bump DOTNS_SALT_VERSION"), so a stage interrupted between the two fails every plain re-run. This was reproduced on a devnet fork: the adapter stopped after `DeployCore`'s fifth transaction (the `StoreFactory` implementation) and attempts 2 and 3 both failed on that guard. The recovery is `forge script scripts/deploy/<Stage>.s.sol:<Stage> <the same flags> --resume`, which sends the unsent transactions of the saved broadcast without re-simulating (on the same fork it sent the seven pending `DeployCore` transactions, nonces 6 to 12, and exited 0), followed by a plain re-run of the pipeline, which adopts what landed and rebuilds the manifest. That recovery is not automated and has not been exercised end to end; rehearse it on a fork before the production run.

*Run resume* (`DEPLOY_RESUME=1`, workflow input `resume`; written but untested, to be exercised on a fork before the production run): when the attempts are exhausted or the job died, dispatch again with `resume`. Preflight then takes the factory from the chain instead of the key's nonce: `FACTORY_NONCE` when set (0 in `live`, where the nonce-0 rule stands), else the highest nonce below the current one whose CREATE address holds the `Create3Factory` runtime code (the interrupted run began with its factory, and every later transaction of the key belonged to that run). The expected set is derived from that factory as usual; an occupied expected address passes only when its runtime code equals the artefact the pipeline deploys there (`scripts/deploy/expected-code.py`: `Create3Factory`, `ERC1967Proxy` for the 13 proxies, `UpgradeableBeacon` for the beacons, the contract's own artefact otherwise, with the compiler's immutable ranges masked on both sides), and every occupied owned contract must still answer `owner()` with the sender. Anything else at an expected address is a squat and is refused. The minimum balance scales with the addresses still empty (floor `RESUME_MIN_FLOOR_DOT`, 8, for the wiring, the handover and fee headroom). `deployall.sh` then finds the factory present and skips it, and every stage adopts what is there. Without `resume`, live mode stays strict: nonce 0, every expected address empty. A run that died during the handover is resumed by re-running the handover, not the deploy (`handover.sh` counts contracts already owned by `NEW_OWNER` as done); the deploy step refuses a set the sender no longer owns.

*Why a re-run is safe.* The pre-screen above is not the authority; the stages are. `BaseDeployer._deployCreate3` predicts the CREATE3 address and, when it holds code, adopts it only after `_requireExpectedCode` proved the runtime code is this artefact built with this run's constructor arguments (exact codehash for artefacts without immutables, immutable ranges masked otherwise), reverting on anything else; `_broadcastDeployUups` further requires the implementation to be present together with its proxy and reads the ERC1967 slot to confirm the adopted proxy delegates to that implementation. Every initialiser runs inside the proxy's constructor (`ERC1967Proxy(implementation, initialiserCalldata)`), so a proxy either exists initialised or not at all, and an adopted proxy is never re-initialised. `StoreFactory.initialize` mints both beacons in that same transaction, so the beacons exist exactly when the proxy does. The non-deploy calls repeat without reverting, so a retried stage resends them and the only cost is the redundant transactions: `DotnsProtocolRegistry.set` returns early on an equal value (`DeployCore` re-registers the factory with it, `WireDeployments` re-sets the 15 keys), `DotnsRegistrar.addController` and `DotnsProtocolRegistry.setExpectedCodehash`/`setProtocolVersion` overwrite with the same value, and `DeployRecords` registers the cost model only when `modelOf(version)` is empty (the one write that would revert, `AlreadyRegistered`). A retried `WireDeployments` therefore costs at most its full 34 transactions again. `DeployCreate3Factory` asserts the key's nonce, so `factory.sh` checks the address for code inside every attempt and a factory that landed while the RPC was down is found, not resent.

**Expected set.** `scripts/deploy/expected-set.sh [--nonce N] <deployer>` prints the address set a fresh deploy from that key lands, without a chain: factory = the deployer's CREATE at nonce `N` (default 0), every other address = Solady CREATE3 over the `BaseDeployer` salt, beacons = CREATEs of the `StoreFactory` proxy at nonces 2 and 4. `--factory <address>` starts from a known factory instead. With the default nonce it reproduces `deployments/expected.json` for the CI factory key.

**Local rehearsal.** `scripts/deploy/rehearse-fork.sh` runs preflight, deploy, handover, verify and sweep with the keystore signer (`DEPLOY_MODE=fork`) on a local chopsticks fork of Polkadot Asset Hub (ports `CHOPSTICKS_PORT`, `ETH_RPC_PORT`; `AH_ENDPOINTS` for a devnet fork), with a fresh throwaway key by default. `USED_KEY_TXS=N` sends `N` transfers first to rehearse a used-key deploy. It prints the cost per step and moves the manifest and broadcasts into its `WORK_DIR`. `scripts/deploy/substrate.py` carries the Substrate reads (balances, mapping, same-chain check) and the fork funding.

## Troubleshooting

If the adapter is not responding, confirm Docker is running and that port 8545 is free. The compose health check uses eth_chainId against http://localhost:8545.

If the deploy script says PRIVATE_KEY is required, the configured ACCOUNT_NAME has not yet been imported into the Foundry keystore. Populate .env once, or provide PRIVATE_KEY and ACCOUNT_PASSWORD through the shell environment.

If the deploy script fails after importing the key, .env is intentionally left in place. Correct the failed field or network issue and rerun the same command.

If the deploy script succeeds, .env should be gone. Future runs should use the keystore account and should not require the deployer private key.

If a stage fails part way through, the runner retries it (`DEPLOY_STAGE_ATTEMPTS`, default 3, after waiting for the RPC); if every attempt fails, rerun the same command. Each stage adopts any contract already at its deterministic address and skips re-initialising an adopted proxy, so the rerun resumes from where it stopped and deploys only what is missing. Later stages read the deployment manifest for wire-up, so if you edit the manifest by hand keep it consistent with what is actually on chain, or the wire-up can fail.

A failure naming a beacon implementation or an unexpected occupant usually means the chain and the checked-out release disagree rather than that anything is wrong on chain. Check out the release the chain is actually running before rerunning.

## Addresses

The deployment manifest for a network is the only place in this repository that records its addresses:

```text
deployments/<network>/<chain-id>.json
```

Every network deployed through the shared CREATE3 factory lands on the same address set, so those manifests agree with each other; a chain deployed through a different factory has its own set, and a chain id alone does not identify one, since several networks report the same id. Only the TLD differs per network among the networks below.

| Network | TLD |
| --- | --- |
| Paseo Asset Hub Previewnet | `.testnet` |
| Paseo Asset Hub Next V2 | `.paseo` |

Each release also publishes the same addresses as `deployments.json`, attached to the release and at the root of `dotns-abis-<tag>.zip`, for consumers outside this repository. See [`RELEASE_ARTIFACTS.md`](./RELEASE_ARTIFACTS.md).

Prefer reading an address from the protocol registry at runtime. Every consumer contract exposes `protocolRegistry`, and the registry resolves each well-known key in `DotnsConstants`, so one known address is enough to reach the rest and the chain stays the authority.
