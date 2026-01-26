# Dotns

Smart contracts for registering `.dot` names on Polkadot

## Diagrams

### Registration flow

![Registration flow](./diagrams/registration.png)

### Subnode creation flow

![Subnode creation](./diagrams/subname.png)

### CID flow (Bulletin Chain)

![CID flow](./diagrams/cid.png)

### System diagram

![System diagram](./diagrams/system.png)

## Deployment note

To deploy on Paseo you need a local ETH-RPC adapter.

A `docker-compose` file is provided. Start it first, then run the deployment scripts from `package.json`, for example:

```bash
bun run deploy:testnet
```

## Contracts

### `DotnsRegistrarController`

Commit–reveal controller that validates commitments, enforces pop rules checks, and orchestrates registration side effects (minting, registry wiring, reverse record, Store writes, refunds).

### `DotnsRegistrar`

ERC721-backed registrar that mints ownership of label IDs (labelhashes). Minting is restricted to authorised controllers.

### `DotnsRegistry`

Forward registry mapping node → `(owner, resolver)` and supporting subnode creation. Privileged node wiring is restricted to the configured registrar controller.

### `PopRules`

PoP-aware name classification and pricing. Enforces base-name reservation rules derived from Lite-eligible registrations.

### `DotnsReverseResolver`

Reverse records mapping address → primary name. Writes are restricted to an authorised registrar/controller.

### `DotnsContentResolver`

Stores `contenthash` and text records per node. Writes require node ownership (or approved operator if enabled).

### `DotnsResolver`

Stores forward-resolution address records per node. Writes require node ownership.

### `StoreFactory` and `Store`

Per-user storage used to persist DotNS-written records. Deployed to Paseo

### Deployments
| Contract                 | Address                                    |
| ------------------------ | ------------------------------------------ |
| StoreFactory             | 0xF8e838FF0E5955de7bdDD367fA89c89575722615 |
| DotnsRegistrar           | 0x68cE3f3b3819279861CcEf1d703Aa358b4993650 |
| DotnsReverseResolver     | 0xb8e019D716a718Ba2C7a8649215AcB7f31aa5147 |
| DotnsRegistry            | 0xd31ACEFD8E40078375BFF392805BBc0301f0aF4A |
| DotnsContentResolver     | 0xb3d23aDC08dc3bb8b1130579e81449afbA5cc3c2 |
| DotnsResolver            | 0x34196DC986e600bDDbb5F43BF77D8cBe6ad05b20 |
| PopRules                 | 0xdE40254fF6470CE8b6683d2FCFD0599B2BcfC3Af |
| DotnsRegistrarController | 0x2CB1dE90013C55f779Ca6894a66142571e1af41D |


### Mental model for new features

Treat the chain as the database. Assume no servers and no indexers. If a feature needs an offchain service to be usable, it is not a DotNS feature.

This has a practical implication: every feature must come with an explicit query path. A client should be able to start from a small set of known contracts and find everything it needs with a bounded number of calls.

Rules of thumb:

- State is the source of truth. Events are for observability.
- Discovery must be deterministic. If something is created, store where to find it.
- Avoid “scan and reconstruct”. Do not require replaying logs from genesis to recover user state.
- Prefer simple keys. `node`, `labelhash`, `owner`, `commitment` should be enough to locate related data.
- If you need lists, make them enumerable onchain with pagination. Do not assume an indexer will build the list.
- If a rule matters for funds or correctness, enforce it onchain. Offchain checks are optional UX.

A quick checklist for a PR adding a feature:

- Where is the canonical state stored?
- From which known contract can a client discover it?
- What are the exact view functions needed to read it without scanning?
- How does a client list relevant items (if listing is required), and how is it paginated?

### Build

```bash
forge build
```

### Test

```bash
forge clean
forge test
```
