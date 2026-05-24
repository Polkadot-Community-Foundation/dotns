# DotNS Deployments

Current deployment addresses and developer deployment notes for dotNS contracts.

## What this file is for

This file is the operational companion to the README. It explains how to run the local ETH-RPC adapter, how to deploy DotNS, where deployment manifests are written, and which addresses are currently live on the supported Paseo environments.

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
| Deploy core | scripts/deploy/DeployCore.s.sol | Foundational name-ownership layer: store factory, registrar, reverse resolver, and forward registry. |
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

## Deployment manifests

Every stage writes its output to a shared JSON manifest. Later stages read the addresses written by earlier stages from the same file.

The manifest folder is selected from the current chain id:

| Chain id | Manifest folder |
| ---: | --- |
| 420420422 | deployments/passethub-testnet |
| 420420417 | deployments/paseo-assethub |
| 420420420 | deployments/paseo-local |
| other | deployments/localhost |

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

## Paseo Asset Hub Previewnet

| Contract | Address |
| --- | --- |
| DotnsProtocolRegistry | 0xc07A2F24387DA27283CD87b9F24573b74C9e0c9b |
| DotnsRegistrar | 0x6c40817cdb96Ab57A4d9E9fa21D0eEa8307BDDE8 |
| DotnsRegistry | 0xE6c0fB6D5492666144A8a4a015E25a98ACa604cA |
| DotnsRegistrarController | 0x732C38082CFAebed505A46e4e2D6414154694580 |
| DotnsPopController | 0xfE1e25E8d521CaaA8055301CA61Ec3557263Ca76 |
| PopRules | 0x5f2Dd23Ee3ceD39B293701ccE8355DdDd83Cd324 |
| DotnsResolver | 0x5E174c960F5276Bd0387F200cE42f98fe927E220 |
| DotnsReverseResolver | 0xd5C3dcC7CE44593fEB1D72017A3539c4dB14e54a |
| DotnsContentResolver | 0x108376A5B6DDc6BE3201C94Fd169BE444f220076 |
| DotnsPopResolver | 0x29Ace5d2C57109c82A30Db175e645880572c6369 |
| DotnsNameEscrow | 0x034b072eB8AF5cEfd820390bfe239bD911174ad2 |
| StoreFactory | 0x9C38DFec452391696a8f0D3daFE71F7Eb29e08f8 |
| LabelStoreBeacon | 0x6B609A89Fec9898B441E17f1618670bdD08c437e |
| UserStoreBeacon | 0xbeb79e8BB2bC610822e8748e5439B9D890d88FF5 |

## Paseo Asset Hub Next V2

| Contract | Address |
| --- | --- |
| DotnsProtocolRegistry | 0x5Caef84563fc980178e28417414aa65bA32f6B4e |
| DotnsRegistrar | 0x885b8085bA92A31c4ef52076f77379E647ECC399 |
| DotnsRegistry | 0x8877344A885682523B4613779C95688ed7037BfD |
| DotnsRegistrarController | 0x320b72c6e70D5a631d835FfD95915B288b26E6Be |
| DotnsPopController | 0xaC8A28b60832E6E22bC19bD9Ee273C008576Bde4 |
| RootGatewayDispatcher | 0xF470Dd693ED557b33f8775476776532D99Fb60d9 |
| PopRules | 0x2002C1c15b88632Ad01c7770f6EbE1Ca05c8472E |
| DotnsResolver | 0x0cCdfea1a5E62DE116BF6cA79D397798d49e351E |
| DotnsReverseResolver | 0x025D5c4b10bD9723DeA2F4518aeD5B761DE08CDc |
| DotnsContentResolver | 0x2c9FF5D9136DBE5814C7B4FDbeDC15273a776663 |
| DotnsPopResolver | 0xB992e74cBeaf1Fd71310f85D1944d3A0c15C4c73 |
| DotnsNameEscrow | 0x6F7068c04487a90BFB42b128B84231c252b3017a |
| StoreFactory | 0x0DE5De70d61cc6b44B45d6595afDe8dB9b55bc31 |
| LabelStoreBeacon | 0xD033F7Ada687E8BC776928AB239505F9f0479Ce7 |
| UserStoreBeacon | 0x7eD9b7D137Fa535965048F93b3B0248fEd2fcd32 |
