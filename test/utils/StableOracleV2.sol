// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {StableOracle} from "../../contracts/ethregistrar/StableOracle.sol";

/// @notice Upgraded StableOracle to v2
///         This is to show that the contract has been updated
/// @custom:oz-upgrades-from contracts/ethregistrar/StableOracle.sol:StableOracle
contract StableOracleV2 is StableOracle {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {}

    function upgraded() public pure returns (string memory) {
        return "Im upgraded to v2";
    }
}
