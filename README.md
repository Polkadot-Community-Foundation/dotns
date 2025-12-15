# Dotns

Smart contracts for registering .dot names on Polkadot. This project uses foundry which can be downloaded [here](https://getfoundry.sh/introduction/installation)

## Registry

The registry is the core contract for dot resolution. All lookups query the registry first. It maintains a list of domains, recording owner, resolver, and TTL for each, and allows owners to modify that data.

### ENS.sol

Interface of the ENS Registry.

### ENSRegistry

Central contract for looking up resolvers and owners for domains.

### FIFSRegistrar

First-in-first-served registrar that issues (sub-)domains to the first account requesting them.

### ReverseRegistrar

Manages reverse resolution via the .addr.reverse special-purpose TLD.

### TestRegistrar

Provides instant domain claims for testing on test networks. Domains expire 28 days after claiming.

## EthRegistrar

Registrar for the .dot TLD. Audited by ConsenSys Diligence: [audit report](https://github.com/ConsenSys/ens-audit-report-2019-02).

### BaseRegistrar

Owns the TLD in the ENS registry. Functionality:

- Owner may add and remove controllers
- Controllers register new domains and renew existing ones (cannot change ownership or reduce expiration)
- Name owners transfer ownership to another address
- Name owners reclaim ownership in the ENS registry if lost
- Owners of names in the interim registrar transfer them during the 1-year transition period with full deposit return

This separation guarantees continued ownership of existing names while permitting changes in registration and renewal mechanisms.

### DotRegistrarController

First registration controller implementation. Functionality:

- Owner sets price oracle contract determining registration and renewal costs based on name and duration
- Owner withdraws collected funds
- Users register new names via commit/reveal process and appropriate fee
- Any user can renew a domain by paying the fee

Commit/reveal process prevents frontrunning:

1. User commits to a hash containing the name and a secret value
2. After minimum delay and before expiration, user calls register with name and secret
3. If valid commitment exists and preconditions are met, name is registered

Minimum delay and expiry prevent miners or users from frontrunning registrations.

### StableOracle

Oracle implementation allowing owner to define configurable rules, including pricing for spam protection and Proof of Personhood logic based on name length. Uses a fiat-denominated price feed to establish fixed fiat price per name. Pricing is for spam prevention only and economically insignificant. Contract is upgradeable as Proof of Personhood requirements may evolve.

DotRegistrarController calls StableOracle during registration to verify user satisfies required personhood status. StableOracle implements name reservation mechanics: registering `iamkarim12` reserves base name `iamkarim` (numeric suffix removed) for 12 weeks, preventing others from registering the base name during this window.

## Resolvers

General-purpose ENS resolver for standard use cases. Permits updates to ENS records by the owner of the corresponding name.

PublicResolver includes these profiles implementing different EIPs:

- ABIResolver = EIP 205 - ABI support (`ABI()`)
- AddrResolver = EIP 137 - Contract address interface. EIP 2304 - Multicoin support (`addr()`)
- ContentHashResolver = EIP 1577 - Content hash support (`contenthash()`)
- InterfaceResolver = EIP 165 - Interface Detection (`supportsInterface()`)
- NameResolver = EIP 181 - Reverse resolution (`name()`)
- PubkeyResolver = EIP 619 - SECP256k1 public keys (`pubkey()`)
- TextResolver = EIP 634 - Text records (`text()`)
- DNSResolver = Experimental DNS domain hosting on Ethereum blockchain via ENS

## Developer guide

### Setup

```bash
git clone https://github.com/ensdomains/ens-contracts
cd ens-contracts
bun i
```

### Tests

```bash
bun run test
```

### Deployment

Set up an eth-rpc adapter. Public RPC endpoints are unreliable and cause transaction failures.

Start adapter:

```bash
./bin/eth-rpc --node-rpc-url [SUBSTRATE_NODE_RPC_URL] --rpc-port 8545
```

Substrate node RPC URL: `wss://testnet-passet-hub.polkadot.io`, Westend, or any node supporting the Revive pallet.

Deploy:

```bash
bun run deploy:paseo:local
```

"local" refers to using the locally running eth-rpc adapter to forward transactions, enabling reliable Forge script execution.

eth-rpc adapter downloads automatically via pre/post-install scripts during `bun install`.

### Local Testing 

This requires 

## Upgrades

Some contracts need upgrading to newer Solidity versions when extending them to create upgradeable contracts. This requires patching due to OpenZeppelin contract version differences. The goal is aligning all versions to use the latest or another determined version.
