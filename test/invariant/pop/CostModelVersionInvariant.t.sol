// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {CostModelVersionHandler} from "./CostModelVersionHandler.t.sol";

/// @title CostModelVersionInvariantTest
/// @notice Asserts the cost-model registry stays coherent under any sequence of model
///         registrations and current-version moves, including reverting to older versions.
contract CostModelVersionInvariantTest is BaseDotns {
    /// @notice Handler driving model registration and version moves. Prices are ghost-tracked.
    CostModelVersionHandler public handler;

    function setUp() public override {
        super.setUp();
        handler = new CostModelVersionHandler(
            costModelRegistry, popRules, dotnsRegistrarController, owner, ed
        );
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.registerModel.selector;
        selectors[1] = handler.pointCurrent.selector;
        selectors[2] = handler.bindMoveReveal.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Every registered version keeps returning the same amount for the life of the run,
    ///         because each model is immutable no matter how the current pointer moves.
    function invariant_registered_versions_price_is_immutable() public view {
        uint256 count = handler.versionCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 version = handler.versions(i);
            assertEq(
                costModelRegistry.priceForBaseLengthAtVersion(version, 7),
                handler.expectedAt7(version),
                "version price at 7 must not move"
            );
            assertEq(
                costModelRegistry.priceForBaseLengthAtVersion(version, 9),
                handler.expectedAt9(version),
                "version price at 9 must not move"
            );
            assertEq(
                costModelRegistry.priceForBaseLengthAtVersion(version, 12),
                handler.expectedAt12(version),
                "version price at 12 must not move"
            );
        }
    }

    /// @notice The current pointer always resolves to its registered model, and the fresh price
    ///         PopRules serves equals that model's amount.
    function invariant_current_pointer_is_coherent() public view {
        uint256 current = costModelRegistry.currentVersion();
        assertEq(
            address(costModelRegistry.current()),
            address(costModelRegistry.modelOf(current)),
            "current must resolve to its registered model"
        );

        string memory label = "longnamehere";
        assertEq(
            popRules.price(label),
            costModelRegistry.priceForBaseLengthAtVersion(current, bytes(label).length),
            "fresh price must equal the current model"
        );
    }
}
