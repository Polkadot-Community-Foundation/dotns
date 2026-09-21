// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {DeployCreate3Factory} from "../../../scripts/deploy/DeployCreate3Factory.s.sol";

/// @notice Covers the single-purpose-key guard on the standalone factory deploy
///         script. The factory address is nonce-derived, so the script must
///         only deploy from a pristine key to keep that address reproducible
///         across chain resets. The successful deploy path (`new Create3Factory`)
///         is exercised by the deterministic-deployment suite; here the novel
///         behaviour is the nonce-0 assertion, which cannot be pranked and
///         broadcast in one call, so only the guard is unit-tested.
contract DeployCreate3FactoryTest is Test {
    DeployCreate3Factory private script;

    function setUp() public {
        script = new DeployCreate3Factory();
    }

    function test_revertsWhenDeployerNonceNotZero() public {
        address deployer = makeAddr("reused-key");
        vm.setNonce(deployer, 5);

        vm.prank(deployer);
        vm.expectRevert(
            bytes(
                "DeployCreate3Factory: deployer nonce is 5, expected FACTORY_NONCE=0; the factory address is nonce-derived, so use a single-purpose key at nonce 0 (or set FACTORY_NONCE to the key's current nonce)"
            )
        );
        script.run();
    }
}
