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

## Local Testing

Start anvil:

```bash
anvil --rpc-port 8545
```

Import anvil default accounts into MetaMask:

```
0)  0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
1)  0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
2)  0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
3)  0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
4)  0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
5)  0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
6)  0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
7)  0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
8)  0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
9)  0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
```

For Polkadot, follow [smart contract documentation](https://docs.polkadot.com/develop/smart-contracts/local-development-node/) and import:

```
0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133
```

### Deployment Script

```bash
./deployment.sh
```

Ensure RPC URL matches your node. After deployment, update contract addresses in `src/utils.ts`. Use cast to set up a wallet named revive (or your chosen name) and update deployment script with your wallet name and password.

### Updating Addresses

Update contract addresses in `src/utils.ts`:

```ts
export const SUPPORTED_NETWORKS: Record<number, NetworkConfig & Partial<Deployment>> = {
  420420422: {
    chainId: 420420422,
    chainName: 'Polkadot Hub TestNet',
    nativeCurrency: {
      name: 'Paseo',
      symbol: 'PAS',
      decimals: 18,
    },
    rpcUrls: ['https://testnet-passet-hub-eth-rpc.polkadot.io'],
    blockExplorerUrls: ['https://blockscout-passet-hub.parity-testnet.parity.io/'],
    ensRegistry: '0xe2fB8d393D3A257F709A3a96d234950d00626fa5',
    baseRegistrar: '0xaD5EE06411D18A1Cd1051ED87eAebEE9CD154C64',
    registrarController: '0xfc9FC0f9C67271a84d5Ee1Bd6f14D8527533Bb64',
    bulkRenewal: '0x092b689ed3c08F194EbcB7Fcc7c63d482AaEf2c9',
    publicResolver: '0x41df0d983C94ff742811649278faAa7fBfeb923D',
    oracle: '0x313d4B1c0e4C487A61da6F8ebf00AA01f56be145',
    storeFactory: '0xD1ba8f9dD2218859b4113Fb7eF5C2Ac6D46794f4',
    dotnsRegistrar: '0xa312DA532a0da1F843b09a0172611c2538944b16',
  },
};
```

For new networks, duplicate the structure, replace `chainId`, `chainName`, `rpcUrls`, and `blockExplorerUrls`, then paste new contract addresses.

Example for local Anvil on port 8545:

```ts
1337: {
  chainId: 1337,
  chainName: 'Local Anvil',
  nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
  rpcUrls: ['http://127.0.0.1:8545'],
  blockExplorerUrls: [],
  ensRegistry: 'DEPLOYED_ENS_ADDRESS',
  baseRegistrar: 'DEPLOYED_BASE_REGISTRAR',
  registrarController: 'DEPLOYED_CONTROLLER',
  bulkRenewal: 'DEPLOYED_BULK_RENEWAL',
  publicResolver: 'DEPLOYED_RESOLVER',
  oracle: 'DEPLOYED_ORACLE',
  storeFactory: 'DEPLOYED_STORE_FACTORY',
  dotnsRegistrar: 'DEPLOYED_DOTNS_REGISTRAR',
},
```

### Deployed Addresses Paseo

```json
{
  "ENSRegistry": "0xe2fB8d393D3A257F709A3a96d234950d00626fa5",
  "Root": "0x6a515227BdBA8728a146F1b9e5DA4171FF5Db52e",
  "ReverseRegistrar": "0xFf61Ee76A91b9cbCf74cE142B1b89b778D924e97",
  "BaseRegistrarImplementation": "0xaD5EE06411D18A1Cd1051ED87eAebEE9CD154C64",
  "DummyOracle": "0x313d4B1c0e4C487A61da6F8ebf00AA01f56be145",
  "ExponentialPremiumPriceOracle": "0xD3Cd45D86F3C318c1d3F6358aa836ce604f46580",
  "StaticMetadataService": "0xd7322C9552B323802C278bdeB80681336c4d24BF",
  "NameWrapper": "0x58b4928Cb95aD9fc668616C78c78f84B6ebf5596",
  "DefaultReverseRegistrar": "0x7547f128d60e8DFcefE2517Bc55176b860933644",
  "DotRegistrarController": "0xfc9FC0f9C67271a84d5Ee1Bd6f14D8527533Bb64",
  "StaticBulkRenewal": "0xcF4c2c86096257201a7CA4B367ca680C4ECd1f07",
  "PublicResolver": "0x41df0d983C94ff742811649278faAa7fBfeb923D",
  "GatewayProvider": "0xbdCd5A93148A445A9DA98Ef073bAEbe6F657048c",
  "UniversalResolver": "0xBf0604484853649B7A110f17DDd6af651fC3617D",
  "StoreFactory": "0xD1ba8f9dD2218859b4113Fb7eF5C2Ac6D46794f4",
  "DotnsRegistrar": "0xa312DA532a0da1F843b09a0172611c2538944b16"
}
```

## UI

The `poc` folder contains the frontend built with Vite, Vue 3, TypeScript, and TailwindCSS.

### Running the UI

Navigate to frontend:

```bash
cd poc
```

Install dependencies:

```bash
bun install
```

Start dev server:

```bash
npm run dev
```

Output:

```
➜  Local:   http://localhost:5173/
➜  Network: http://192.168.x.x:5173/
```

Build for production:

```bash
npm run build
```

Preview production build:

```bash
npm run preview
```

### Notes

Run before commits:

```bash
npm run lint:format:fix
```

## Upgrades

Some contracts need upgrading to newer Solidity versions when extending them to create upgradeable contracts. This requires patching due to OpenZeppelin contract version differences. The goal is aligning all versions to use the latest or another determined version.
