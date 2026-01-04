# Dotns

Smart contracts for registering `.dot` names on Polkadot
## Overview

Dotns provides:

- A commit–reveal registration controller for `.dot` labels
- A forward registry (node owner + resolver)
- A reverse resolver (address → primary name)
- A PoP-aware pricing oracle with base-name reservation rules
- Per-user storage (Store) deployed through a factory and used to persist immutable registration records
- Resolvers for contenthash and text records

## Contracts

### Registrars

#### `DotnsRegistrar`
ERC721-backed registrar that mints ownership of label IDs (labelhashes).

Key responsibilities:

- Track whether a label is available
- Mint/register labels to an owner
- Support controller-based registration flow (controller is configured during setup)

#### `DotnsRegistrarController`
Commit–reveal controller that orchestrates the registration flow.

Core responsibilities:

- Validate label availability and commitment age bounds
- Enforce PoP rules and pricing via `PopOracle`
- Mint ownership via `DotnsRegistrar`
- Wire forward registry owner + resolver via `DotnsRegistry`
- Set default reverse record via `DotnsReverseResolver`
- Write an immutable “registered name” record to the user’s `Store` via `StoreFactory`

Key behaviors:

- `commit(bytes32 commitment)` stores the timestamp
- `register(Registration)` validates the commitment window, calls oracle pricing checks, mints the name, wires records, writes to Store, emits `NameRegistered`, refunds excess payment
- `registerReserved(Registration)` is a “reserved path” used for special allocations (no oracle price check)

### Registry

#### `DotnsRegistry`
Forward registry for node ownership and resolution.

Key responsibilities:

- Track owner and resolver per node
- Support controller-driven ownership wiring for registered nodes
- Support subnode ownership for nested namespaces (e.g., subdomains)

Notes:

- Some operations are restricted to the configured registrar controller
- Subnode creation emits `NewOwner(parent, label, owner)` 

### Oracle

#### `PopOracle`
Pricing + PoP enforcement for registrations.

Key responsibilities:

- Classify names by requirement tier (`Reserved`, `PopLite`, `PopFull`, `NoStatus`) based on base length + digit suffix rules
- Enforce reservation rules for base names when Lite-eligible names are registered (e.g., `alice01` reserves `alice`)
- Produce `priceWithCheck(label, user)` metadata used by the controller during registration

Pricing note:
- The “spam price” is applied to names of length >= 9 with a decreasing schedule up to length 15+

### Resolvers

#### `DotnsReverseResolver`
Stores reverse records mapping `address -> string` (e.g., `ed -> "alice.dot"`).

Key points:

- Writes are restricted to an authorised registrar/controller address
- Supports interface detection via ERC165

#### `DotnsContentResolver`
Stores off-chain references for nodes.

Supported records:

- `contenthash(node) -> bytes`
- `text(node, key) -> string`

Authorization:

- Writes require `msg.sender` to be the node owner in `DotnsRegistry`

#### `DotnsResolver`
General forward resolver wrapper (where used in your stack) wired to the `DotnsRegistry` for ownership checks.

### Store

#### `Store`
Per-user key-value storage.

Key behaviors:

- `setValue(key, value)` writes for `msg.sender`
- `setValueFor(user, key, value)` allows authorised writers to write on behalf of a user
- Permanent locking: keys written via a Dotns controller can be locked permanently, preventing overwrite or delete

#### `StoreFactory`
Deploys and tracks per-user `Store` instances.

Key behaviors:

- Each address can deploy exactly one store via `deploy()`
- Tracks deployed stores by owner address
- `transferOwnership(newOwner)` transfers the factory’s ownership mapping (not necessarily the Store’s Ownable owner)

## Developer guide

### Prerequisites

- Foundry: https://getfoundry.sh
- Bun or Node.js for scripts (if you use bun-based tooling in this repo)

### Build

```bash
forge build
