// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StableOracle} from "../../contracts/ethregistrar/StableOracle.sol";

/// @notice Upgraded StableOracle to v2
/// @custom:oz-upgrades-from contracts/ethregistrar/StableOracle.sol:StableOracle
/// @custom:oz-upgrades-unsafe-allow missing-initializer-call
contract StableOracleV2 is StableOracle {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {}

    function upgraded() public pure returns (string memory) {
        return "Im upgraded to v2";
    }
}
