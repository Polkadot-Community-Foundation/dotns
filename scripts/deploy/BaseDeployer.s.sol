// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Create3Factory} from "../../contracts/deploy/Create3Factory.sol";

/// @title BaseDeployer
/// @notice Shared base for the DotNS deploy pipeline. Each concrete stage
///         script reads the manifest from disk (populated by prior stages),
///         deploys its own proxies in its own forge-script process, and writes
///         the updated manifest back.
/// @dev The pipeline is split across separate `forge script` invocations so
///      each OpenZeppelin upgrade-safety validation runs in a fresh EVM
///      simulation. EVM memory gas is quadratic, and a monolithic script
///      accumulates it across every validator FFI call until the block gas
///      limit is hit. Separate processes side-step the accumulation entirely
///      without skipping any OZ check.
/// @custom:security-contact admin@parity.io
abstract contract BaseDeployer is Script {
    /// @notice JSON object key used internally by the `vm.serializeAddress`
    ///         helper. The value is arbitrary; it only has to be stable across
    ///         successive calls within the same run.
    string internal constant MANIFEST_OBJECT_KEY = "dotns.manifest";

    /// @notice Namespace for all DotNS CREATE3 salts.
    /// @dev Do not include the chain ID: the deployment goal is identical
    ///      addresses for identical bytecode and constructor data on every
    ///      chain. Bump this value only when intentionally moving the whole
    ///      deployment address set.
    string internal constant CREATE3_SALT_NAMESPACE = "dotns.create3.v1";

    /// @notice Optional in-memory override used by tests and custom scripts.
    address private create3FactoryOverride;

    /// @notice In-memory JSON string representing the full deployment manifest
    ///         accumulated across this stage's calls to `logDeployment`.
    string private manifestJson;

    /// @notice Disk path the current stage reads from and writes to. Populated
    ///         by `initDeployment`.
    string private manifestPath;

    /// @notice Loads the existing deployment manifest for `(subdirectory, filename)`
    ///         if one exists; otherwise begins a fresh in-memory object. Every
    ///         stage must call this first so subsequent `_readAddress` / `logDeployment`
    ///         calls see the correct baseline.
    /// @dev The disk format is `{"ContractName": "0x..."}`. Using foundry's
    ///      native serializer keeps parsing and writing symmetric: the same
    ///      `vm.serializeAddress` value feeds both `vm.writeFile` and
    ///      `vm.parseJsonAddress`.
    /// @param subdirectory Network-specific folder under `deployments/`.
    /// @param filename Stem of the manifest file (for example `block.chainid`).
    function initDeployment(string memory subdirectory, string memory filename) internal {
        manifestPath = _deploymentPath(subdirectory, filename);

        if (vm.exists(manifestPath)) {
            // Prime foundry's internal serializer with every existing entry so
            // subsequent `logDeployment` calls extend the object rather than
            // replace it. `vm.serializeAddress` tracks an object per string
            // key; the FIRST call with a given key starts a fresh object, so
            // we have to re-insert every prior address before the first new
            // log.
            // forge-lint: disable-next-line(unsafe-cheatcode)
            string memory priorJson = vm.readFile(manifestPath);
            string[] memory names = vm.parseJsonKeys(priorJson, "$");

            for (uint256 i = 0; i < names.length; ++i) {
                address addr = vm.parseJsonAddress(priorJson, string.concat(".", names[i]));
                manifestJson = vm.serializeAddress(MANIFEST_OBJECT_KEY, names[i], addr);
            }
            if (names.length == 0) {
                manifestJson = vm.serializeAddress(MANIFEST_OBJECT_KEY, "_seed", address(0));
            }
        } else {
            // `vm.serializeAddress` requires at least one write before it will
            // emit a valid object. We seed with a sentinel address(0) under
            // a reserved key so subsequent writes have a base to extend.
            manifestJson = vm.serializeAddress(MANIFEST_OBJECT_KEY, "_seed", address(0));
        }
    }

    /// @notice Appends a single `name => address` entry to the in-memory manifest.
    /// @dev Overwrites any existing entry under the same name. Stages should
    ///      not reuse names across contracts; the wire stage relies on stable
    ///      naming to look up prior-stage addresses.
    /// @param name Label under which the address is recorded.
    /// @param addr Proxy or contract address to record.
    function logDeployment(string memory name, address addr) internal {
        _requireContract(name, addr);
        manifestJson = vm.serializeAddress(MANIFEST_OBJECT_KEY, name, addr);
    }

    /// @notice Writes the accumulated manifest to disk. Idempotent within a
    ///         stage (safe to call once at the end of `run()`).
    function saveDeployments() internal {
        string[] memory mkdirInputs = new string[](3);
        mkdirInputs[0] = "mkdir";
        mkdirInputs[1] = "-p";
        mkdirInputs[2] = _parentDirectory(manifestPath);
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.ffi(mkdirInputs);

        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(manifestPath, manifestJson);
    }

    /// @notice Reads an address recorded by a prior stage from the manifest on
    ///         disk. Useful for wire-up stages that must see every proxy the
    ///         earlier stages deployed.
    /// @dev Reverts if the name is not present. Callers should call
    ///      `initDeployment` first so the manifest path is resolved.
    /// @param name The label under which the target address was recorded.
    /// @return addr The recorded address.
    function _readAddress(string memory name) internal view returns (address addr) {
        string memory key = string.concat(".", name);
        addr = vm.parseJsonAddress(manifestJson, key);
        _requireContract(name, addr);
    }

    function _requireContract(string memory name, address addr) internal view {
        require(addr != address(0), string.concat(name, ": zero address"));
        require(addr.code.length != 0, string.concat(name, ": no code"));
    }

    /// @notice Deploys a UUPS implementation and ERC1967 proxy through CREATE3
    ///         inside its own broadcast scope, labels the proxy for trace
    ///         readability, and records it on the manifest.
    /// @dev Full OZ upgrade-safety validation runs on every call. The helper
    ///      exists so every stage script shares one canonical deploy shape
    ///      rather than repeating the validation, broadcast, label, and log
    ///      sequence. Salts are derived from a stable DotNS namespace plus the
    ///      manifest label, so addresses stay the same across chains as long as
    ///      the deployer, bytecode, constructor args, and label remain stable.
    /// @param owner Broadcasting account; becomes the proxy owner.
    /// @param artefact Fully-qualified artefact name (`File.sol:Contract`).
    /// @param initialiserCalldata ABI-encoded initialiser call.
    /// @param label Trace / manifest identifier.
    /// @return proxy Address of the deployed UUPS proxy.
    function _broadcastDeployUups(
        address owner,
        string memory artefact,
        bytes memory initialiserCalldata,
        string memory label
    )
        internal
        returns (address proxy)
    {
        Options memory opts;
        Upgrades.validateImplementation(artefact, opts);

        vm.startBroadcast(owner);
        address implementation =
            _deployCreate3(artefact, opts.constructorData, _create3Salt(label, "implementation"));
        proxy = _deployCreate3(
            "ERC1967Proxy.sol:ERC1967Proxy",
            abi.encode(implementation, bytes("")),
            _create3Salt(label, "proxy")
        );
        if (initialiserCalldata.length != 0) {
            (bool ok, bytes memory ret) = proxy.call(initialiserCalldata);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
        vm.stopBroadcast();
        vm.label(proxy, label);
        logDeployment(label, proxy);
    }

    /// @notice Deploys a non-upgradeable contract with CREATE3 in a broadcast
    ///         scope, labels it, and records it in the manifest.
    /// @param owner Broadcasting account.
    /// @param artefact Fully-qualified artefact name.
    /// @param constructorData ABI-encoded constructor arguments.
    /// @param label Trace / manifest identifier.
    /// @return deployed Address of the deployed contract.
    function _broadcastDeployCreate3(
        address owner,
        string memory artefact,
        bytes memory constructorData,
        string memory label
    )
        internal
        returns (address deployed)
    {
        vm.startBroadcast(owner);
        deployed = _deployCreate3(artefact, constructorData, _create3Salt(label, "contract"));
        vm.stopBroadcast();
        vm.label(deployed, label);
        logDeployment(label, deployed);
    }

    /// @notice Sets the CREATE3 factory address used by deterministic deploy
    ///         helpers. Intended for tests and custom bootstrap scripts.
    function _setCreate3Factory(address factory) internal {
        require(factory.code.length != 0, "Create3Factory: no code");
        create3FactoryOverride = factory;
    }

    /// @notice Predicts the CREATE3 address used by the deterministic deploy
    ///         helpers for the same inputs.
    function _predictCreate3(
        string memory label,
        string memory kind
    )
        internal
        view
        returns (address predicted)
    {
        predicted = _create3Factory().predict(_create3Salt(label, kind));
    }

    function _deployCreate3(
        string memory artefact,
        bytes memory constructorData,
        bytes32 salt
    )
        internal
        returns (address deployed)
    {
        bytes memory bytecode = _creationBytecode(artefact, constructorData);
        address predicted = _create3Factory().predict(salt);
        require(predicted.code.length == 0, string.concat(artefact, ": CREATE3 target occupied"));

        deployed = _create3Factory().deploy(salt, bytecode);
        require(deployed == predicted, string.concat(artefact, ": CREATE3 deploy failed"));
    }

    function _creationBytecode(
        string memory artefact,
        bytes memory constructorData
    )
        internal
        view
        returns (bytes memory)
    {
        return abi.encodePacked(vm.getCode(artefact), constructorData);
    }

    function _create3Factory() internal view returns (Create3Factory factory) {
        address factoryAddress = create3FactoryOverride;
        if (factoryAddress == address(0)) {
            factoryAddress = vm.envOr("DOTNS_CREATE3_FACTORY", address(0));
        }
        require(factoryAddress.code.length != 0, "DOTNS_CREATE3_FACTORY: no code");
        factory = Create3Factory(payable(factoryAddress));
    }

    function _create3Salt(string memory label, string memory kind) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(CREATE3_SALT_NAMESPACE, ":", label, ":", kind));
    }

    function _deploymentPath(
        string memory subdirectory,
        string memory filename
    )
        private
        pure
        returns (string memory)
    {
        return string.concat("./deployments/", subdirectory, "/", filename, ".json");
    }

    function _parentDirectory(string memory path) private pure returns (string memory) {
        bytes memory bytesPath = bytes(path);
        uint256 lastSlash = bytesPath.length;
        for (uint256 i = bytesPath.length; i > 0; --i) {
            if (bytesPath[i - 1] == 0x2f) {
                lastSlash = i - 1;
                break;
            }
        }
        bytes memory parent = new bytes(lastSlash);
        for (uint256 i = 0; i < lastSlash; ++i) {
            parent[i] = bytesPath[i];
        }
        return string(parent);
    }
}
