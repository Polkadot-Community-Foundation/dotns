# ENS

[![Build Status](https://travis-ci.org/ensdomains/ens-contracts.svg?branch=master)](https://travis-ci.org/ensdomains/ens-contracts)

For documentation of the ENS system, see [docs.ens.domains](https://docs.ens.domains/).

## npm package

This repo doubles as an npm package with the compiled JSON contracts

```js
import {
  BaseRegistrar,
  BaseRegistrarImplementation,
  BulkRenewal,
  ENS,
  ENSRegistry,
  ENSRegistryWithFallback,
  ETHRegistrarController,
  FIFSRegistrar,
  LinearPremiumPriceOracle,
  PriceOracle,
  PublicResolver,
  Resolver,
  ReverseRegistrar,
  StableOracle,
  TestRegistrar,
} from '@ensdomains/ens-contracts'
```

## Importing from solidity

```
// Registry
import '@ensdomains/ens-contracts/contracts/registry/ENS.sol';
import '@ensdomains/ens-contracts/contracts/registry/ENSRegistry.sol';
import '@ensdomains/ens-contracts/contracts/registry/ENSRegistryWithFallback.sol';
import '@ensdomains/ens-contracts/contracts/registry/ReverseRegistrar.sol';
import '@ensdomains/ens-contracts/contracts/registry/TestRegistrar.sol';
// EthRegistrar
import '@ensdomains/ens-contracts/contracts/ethregistrar/BaseRegistrar.sol';
import '@ensdomains/ens-contracts/contracts/ethregistrar/BaseRegistrarImplementation.sol';
import '@ensdomains/ens-contracts/contracts/ethregistrar/BulkRenewal.sol';
import '@ensdomains/ens-contracts/contracts/ethregistrar/ETHRegistrarController.sol';
import '@ensdomains/ens-contracts/contracts/ethregistrar/LinearPremiumPriceOracle.sol';
import '@ensdomains/ens-contracts/contracts/ethregistrar/PriceOracle.sol';
import '@ensdomains/ens-contracts/contracts/ethregistrar/StableOracle.sol';
// Resolvers
import '@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol';
import '@ensdomains/ens-contracts/contracts/resolvers/Resolver.sol';
```

## Accessing to binary file.

If your environment does not have compiler, you can access to the raw hardhat artifacts files at `node_modules/@ensdomains/ens-contracts/artifacts/contracts/${modName}/${contractName}.sol/${contractName}.json`

## Contracts

## Registry

The ENS registry is the core contract that lies at the heart of ENS resolution. All ENS lookups start by querying the registry. The registry maintains a list of domains, recording the owner, resolver, and TTL for each, and allows the owner of a domain to make changes to that data. It also includes some generic registrars.

### ENS.sol

Interface of the ENS Registry.

### ENSRegistry

Implementation of the ENS Registry, the central contract used to look up resolvers and owners for domains.

### ENSRegistryWithFallback

The new implementation of the ENS Registry after [the 2020 ENS Registry Migration](https://docs.ens.domains/ens-migration-february-2020/technical-description#new-ens-deployment).

### FIFSRegistrar

Implementation of a simple first-in-first-served registrar, which issues (sub-)domains to the first account to request them.

### ReverseRegistrar

Implementation of the reverse registrar responsible for managing reverse resolution via the .addr.reverse special-purpose TLD.

### TestRegistrar

Implementation of the `.test` registrar facilitates easy testing of ENS on the Ethereum test networks. Currently deployed on Ropsten network, it provides functionality to instantly claim a domain for test purposes, which expires 28 days after it was claimed.

## EthRegistrar

Implements an [ENS](https://ens.domains/) registrar intended for the .dot TLD.

These contracts were audited by ConsenSys Diligence; the audit report is available [here](https://github.com/ConsenSys/ens-audit-report-2019-02).

### BaseRegistrar

BaseRegistrar is the contract that owns the TLD in the ENS registry. This contract implements a minimal set of functionality:

- The owner of the registrar may add and remove controllers.
- Controllers may register new domains and extend the expiry of (renew) existing domains. They can not change the ownership or reduce the expiration time of existing domains.
- Name owners may transfer ownership to another address.
- Name owners may reclaim ownership in the ENS registry if they have lost it.
- Owners of names in the interim registrar may transfer them to the new registrar, during the 1 year transition period. When they do so, their deposit is returned to them in its entirety.

This separation of concerns provides name owners strong guarantees over continued ownership of their existing names, while still permitting innovation and change in the way names are registered and renewed via the controller mechanism.

### EthRegistrarController

EthRegistrarController is the first implementation of a registration controller for the new registrar. This contract implements the following functionality:

- The owner of the registrar may set a price oracle contract, which determines the cost of registrations and renewals based on the name and the desired registration or renewal duration.
- The owner of the registrar may withdraw any collected funds to their account.
- Users can register new names using a commit/reveal process and by paying the appropriate registration fee.
- Users can renew a name by paying the appropriate fee. Any user may renew a domain, not just the name's owner.

The commit/reveal process is used to avoid frontrunning, and operates as follows:

1.  A user commits to a hash, the preimage of which contains the name to be registered and a secret value.
2.  After a minimum delay period and before the commitment expires, the user calls the register function with the name to register and the secret value from the commitment. If a valid commitment is found and the other preconditions are met, the name is registered.

The minimum delay and expiry for commitments exist to prevent miners or other users from effectively frontrunning registrations.

### SimplePriceOracle

SimplePriceOracle is a trivial implementation of the pricing oracle for the EthRegistrarController that always returns a fixed price per domain per year, determined by the contract owner.

### StableOracle

StableOracle is a price oracle implementation that allows the contract owner to specify pricing based on the length of a name, and uses a fiat currency oracle to set a fixed price in fiat per name.

## Resolvers

Resolver implements a general-purpose ENS resolver that is suitable for most standard ENS use cases. The public resolver permits updates to ENS records by the owner of the corresponding name.

PublicResolver includes the following profiles that implements different EIPs.

- ABIResolver = EIP 205 - ABI support (`ABI()`).
- AddrResolver = EIP 137 - Contract address interface. EIP 2304 - Multicoin support (`addr()`).
- ContentHashResolver = EIP 1577 - Content hash support (`contenthash()`).
- InterfaceResolver = EIP 165 - Interface Detection (`supportsInterface()`).
- NameResolver = EIP 181 - Reverse resolution (`name()`).
- PubkeyResolver = EIP 619 - SECP256k1 public keys (`pubkey()`).
- TextResolver = EIP 634 - Text records (`text()`).
- DNSResolver = Experimental support is available for hosting DNS domains on the Ethereum blockchain via ENS. [The more detail](https://veox-ens.readthedocs.io/en/latest/dns.html) is on the old ENS doc.

## Developer guide

### Prettier pre-commit hook

This repo runs a husky precommit to prettify all contract files to keep them consistent. Add new folder/files to `prettier format` script in package.json. If you need to add other tasks to the pre-commit script, add them to `.husky/pre-commit`

### How to setup

```
git clone https://github.com/ensdomains/ens-contracts
cd ens-contracts
bun i
```

### How to run tests

```
bun run test
```

### How to publish

```
bun run pub
```

## L2 contracts

The only contract in this repo deployed on L2s is `L2ReverseRegistrar` (and its dependency `UniversalSigValidator`).

Anyone can deploy this contract onto any L2, however the contract has functionality which allows using one signature across multiple L2s.
Given this functionality, and [EIP-191](https://eips.ethereum.org/EIPS/eip-191)'s requirement for the intended validator address in the signature, the contract address needs to stay the same between all networks.

To allow for a unified contract address, a Safe and a helper CREATE3 contract are used in the deployment process. The contract can be deployed outside the process, but it means that it will lack the multi-chain signature functionality.

Testnet Safe address: `0x343431e9CEb7C19cC8d3eA0EE231bfF82B584910`
Mainnet Safe address: `0x353530FE74098903728Ddb66Ecdb70f52e568eC1`

## Release flow

### Deployment

When readying a new deployment of certain contracts, bump the deploy script version number to the appropriate new version. Doing this ensures that the new deployment script will run for each network.

Deployment scripts can be run for any specified network found in the [config](hardhat.config.ts#L38), with the following:

```
bun hh --network <network_name> deploy
```

Only scripts that haven't been run on the specified network before will be run.

### Deployment testing

To test deploying contracts and the functionality of them after deployment, there are two basic paths for forking:

- Run an anvil fork, useful for testing locally and iterating. (`anvil --fork-url <url>`)
- Use a Tenderly Virtual TestNet, useful as a staging environment.

When **access to the owner account is available** (testnet only - owner on mainnet is the DAO), you can deploy straight to the fork by replacing the forked network's URL in the hardhat config with your RPC:

```typescript
const config = {
  // ... existing config
  networks: {
    targetNetwork: {
      // ... other network config
      url: 'tenderly-or-anvil-url-here',
    },
  },
}
```

Without access to the owner account, you can deploy via the impersonation script, which makes impersonated accounts from an external node available to hardhat.

```bash
./scripts/deploy-with-impersonation.ts --rpc-url <url> --accounts <addr1> [addr2 ...] [--tags <tags>]

# Testnet usage
./scripts/deploy-with-impersonation.ts --rpc-url <url> --accounts 0x0F32b753aFc8ABad9Ca6fE589F707755f4df2353

# Mainnet usage
./scripts/deploy-with-impersonation.ts --rpc-url <url> --accounts 0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7
```

### Release flow

1. Create a `feature` branch from `staging` branch
2. Make code updates
3. Ensure you are synced up with `staging`
4. Code should now be in a state where you think it can be deployed to production
5. Create a "Release Candidate" [release](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) on GitHub. This will be of the form `v1.2.3-RC0`. This tagged commit is now subject to our bug bounty.
6. Have the tagged commit audited if necessary
7. If changes are required, make the changes and then once ready for review create another GitHub release with an incremented RC value `v1.2.3-RC0` -> `v.1.2.3-RC1`. Repeat as necessary.
8. Deploy to testnet. Open a pull request to merge the deploy artifacts into
   the `feature` branch. Create GitHub release of the form `v1.2.3-testnet` from the commit that has the new deployment artifacts.
9. Get someone to review and approve the deployment and then merge. You now MUST merge this branch into `staging` branch.
10. If any further changes are needed, you can either make them on the existing feature branch that is in sync or create a new branch, and follow steps 1 -> 9. Repeat as necessary.
11. Make a deployment to ethereum mainnet from `staging`. Create a GitHub release of the form `v1.2.3` from the commit that has the new deployment artifacts.
12. Open a PR to merge into `main`. Have it reviewed and merged.

### Cherry-picked release flow

Certain changes can be released in isolation via cherry-picking, although ideally we would always release from `staging`.

1. Create a new branch from `mainnet`.
2. Cherry-pick from `staging` into new branch.
3. Deploy to ethereum mainnet, tag the commit that has deployment artifacts and create a release.
4. Merge into `mainnet`.

### Emergency release process

1. Branch from `main`, make fixes, deploy to testnet (can skip), deploy to mainnet
2. Merge changes back into `main` and `staging` immediately after deploy
3. Create GitHub releases, if you didn't deploy to testnet in step 1, do it now

### Notes

- Deployed code should always match source code in mainnet releases. This may not be the case for `staging`.
- `staging` branch and `main` branch should start in sync
- `staging` is intended to be a practice `main`. Only code that is intended to be released to `main` can be merged to `staging`. Consequently:
  - Feature branches will be long-lived
  - Feature branches must be kept in sync with `staging`
  - Audits are conducted on feature branches
- All code that is on `staging` and `main` should be deployed to testnet and mainnet respectively i.e. these branches should not have any undeployed code
- It is preferable to not edit the same file on different feature branches.
- Code on `staging` and `main` will always be a subset of what is deployed, as smart contracts cannot be undeployed.
- Release candidates, `staging` and `main` branch are subject to our bug bounty
- Releases follow semantic versioning and releases should contain a description of changes with developers being the intended audience


## Misc (Fork Contracts)

This repository contains forked ENS-based contracts for experimental integration and testing.

## Testing Locally

Start an anvil instance using:

```bash
anvil --rpc-port [WHATEVER_PORT — ideally ensure port 8545 is free]
```

Import one of the following private keys into MetaMask (these are from Anvil’s default accounts):

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

For Polkadot please read the instruction on the smart contract documentation [page](https://docs.polkadot.com/develop/smart-contracts/local-development-node/) and import this private key after downloading the relevant artifacts  import the below private key:
`0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133`.

### Deployment

```bash
./deployment.sh
```

Ensure the RPC URL matches your node.
After deployment, update the deployed contract addresses in `src/utils.ts`. Pleas ensure you also use cast to setup a wallet named revive or whatever name you choose and replace the name in the deployment script with your chosen name and password. 

### Updating Addresses

Contract addresses must be updated in:

```ts
// src/utils.ts

e.g. 
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

If deploying to a **new network**, duplicate the structure above, replace the `chainId`, `chainName`, `rpcUrls`, and `blockExplorerUrls`, then paste your new contract addresses.
For example, if deploying locally with **Anvil** on port `8545`, add:

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

This ensures the frontend connects to your local network seamlessly.

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
  "ETHRegistrarController": "0xfc9FC0f9C67271a84d5Ee1Bd6f14D8527533Bb64",
  "StaticBulkRenewal": "0xcF4c2c86096257201a7CA4B367ca680C4ECd1f07",
  "PublicResolver": "0x41df0d983C94ff742811649278faAa7fBfeb923D",
  "GatewayProvider": "0xbdCd5A93148A445A9DA98Ef073bAEbe6F657048c",
  "UniversalResolver": "0xBf0604484853649B7A110f17DDd6af651fC3617D",
  "StoreFactory": "0xD1ba8f9dD2218859b4113Fb7eF5C2Ac6D46794f4",
  "DotnsRegistrar": "0xa312DA532a0da1F843b09a0172611c2538944b16"
}
```

---

## Misc (UI / POC Frontend)

The `poc` folder contains the frontend built with **Vite**, **Vue 3**, **TypeScript**, and **TailwindCSS**.

### Running the UI

1. Navigate into the frontend folder:

   ```bash
   cd poc
   ```

2. Install dependencies:

   ```bash
   npm install
   ```

   or if using **Bun**:

   ```bash
   bun install
   ```

3. Start the development server:

   ```bash
   npm run dev
   ```

   Output will show:

   ```
   ➜  Local:   http://localhost:5173/
   ➜  Network: http://192.168.x.x:5173/
   ```

   Open one of these in your browser.

4. Build for production:

   ```bash
   npm run build
   ```

5. Preview production build:

   ```bash
   npm run preview
   ```

### Available Commands

| Command                   | Description                                      |
| ------------------------- | ------------------------------------------------ |
| `npm run dev`             | Starts the local development server.             |
| `npm run build`           | Builds the app for production.                   |
| `npm run preview`         | Previews the production build locally.           |
| `npm run lint`            | Checks TypeScript and Vue files for lint errors. |
| `npm run lint:fix`        | Automatically fixes lint issues.                 |
| `npm run format`          | Checks code formatting with Prettier.            |
| `npm run format:fix`      | Formats all project files.                       |
| `npm run lint:format:fix` | Runs both lint and format with automatic fixes.  |

### Notes
* Always run:

  ```bash
  npm run lint:format:fix
  ```

  before commits for consistent formatting.
