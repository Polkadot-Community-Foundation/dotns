// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Create3Factory} from "../../contracts/deploy/Create3Factory.sol";

/// @title DeployCreate3Factory
/// @notice Deploys the CREATE3 factory on its own, from a single-purpose key.
/// @dev Every DotNS address is a pure function of the CREATE3 factory address
///      and a stable salt, and the factory address is `keccak(deployer, nonce)`.
///      A key that also runs the pipeline or upgrades cannot guarantee its
///      nonce, so a factory it mints drifts to a new address on every chain
///      reset and shifts the whole address set with it. Deploy the factory from
///      a dedicated key that does nothing else, as its first transaction, then
///      pass the result to the pipeline as `CREATE3_FACTORY` so every run reuses
///      it. The run asserts the deployer is at `FACTORY_NONCE` (default 0) so a
///      reused key cannot silently place the factory at the wrong address; a
///      devnet deploy from a used key sets it to the key's current nonce.
/// @custom:security-contact admin@parity.io
contract DeployCreate3Factory is Script {
    /// @notice Deploys the factory and prints the address to record as
    ///         `CREATE3_FACTORY` for the deploy pipeline.
    /// @return factory Address of the deployed CREATE3 factory.
    function run() external returns (address factory) {
        address deployer = msg.sender;
        uint256 expectedNonce = vm.envOr("FACTORY_NONCE", uint256(0));
        uint64 nonce = vm.getNonce(deployer);
        require(
            nonce == expectedNonce,
            string.concat(
                "DeployCreate3Factory: deployer nonce is ",
                vm.toString(nonce),
                ", expected FACTORY_NONCE=",
                vm.toString(expectedNonce),
                "; the factory address is nonce-derived, so use a single-purpose key at nonce 0 (or set FACTORY_NONCE to the key's current nonce)"
            )
        );

        vm.broadcast(deployer);
        factory = address(new Create3Factory());

        console.log("Create3Factory deployed at:", factory);
        console.log("Pass this address to the deploy pipeline as CREATE3_FACTORY.");
    }
}
