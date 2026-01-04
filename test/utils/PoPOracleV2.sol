// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PopOracle} from "../../contracts/pop/PopOracle.sol";

/// @notice Upgraded PopOracle to v2
/// @custom:oz-upgrades-from contracts/pop/PopOracle.sol:PopOracle
/// @custom:oz-upgrades-unsafe-allow missing-initializer-call
contract PopOracleV2 is PopOracle {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {}

    function upgraded() public pure returns (string memory) {
        return "Im upgraded to v2";
    }
}
