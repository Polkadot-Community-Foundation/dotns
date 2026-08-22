// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {PopRules} from "../../../contracts/pop/PopRules.sol";

/// @title PopRules Governance Handler
/// @notice Drives bounded random governance updates against PopRules for the coherence invariant.
/// @dev Owns PopRules for the campaign so the onlyOwner setters accept its calls. Every input is
///      bound into the setters' valid range, so the handler rejects almost nothing.
contract PopRulesGovernanceHandler is Test {
    PopRules private popRules;

    constructor(PopRules popRules_) {
        popRules = popRules_;
    }

    /// @notice Sets D within the guarded range: at least the current floor, at most the ceiling.
    function setStartingPrice(uint256 seed) external {
        uint256 value = bound(seed, popRules.minPrice(), type(uint256).max / 512);
        popRules.updateStartingPrice(value);
    }

    /// @notice Sets F within the guarded range: at least one wei, at most the current base fee.
    function setMinPrice(uint256 seed) external {
        uint256 value = bound(seed, 1, popRules.startingPrice());
        popRules.updateMinPrice(value);
    }

    /// @notice Opens or closes the short-name market.
    function setShortNames(bool enabled) external {
        popRules.setShortNamesEnabled(enabled);
    }
}
