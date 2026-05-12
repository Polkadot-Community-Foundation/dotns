// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";

contract DotnsProtocolRegistryFuzzTest is BaseDotns {
    function testFuzz_isRegisteredAddress_matches_ground_truth(
        bytes32 k1,
        bytes32 k2,
        bytes32 k3,
        address a,
        address b
    )
        public
    {
        vm.assume(k1 != k2 && k2 != k3 && k1 != k3);
        vm.assume(a != address(0) && b != address(0) && a != b);
        // Exclude fixture-registered addresses so the refcount transitions under test aren't
        // masked by pre-existing references introduced by BaseDotns setUp.
        vm.assume(!protocolRegistry.isRegisteredAddress(a));
        vm.assume(!protocolRegistry.isRegisteredAddress(b));

        vm.startPrank(owner);
        protocolRegistry.set(k1, a);
        protocolRegistry.set(k2, a);
        protocolRegistry.set(k3, b);

        assertTrue(protocolRegistry.isRegisteredAddress(a));
        assertTrue(protocolRegistry.isRegisteredAddress(b));

        // Rotate k2 away from a. a is still referenced by k1.
        protocolRegistry.set(k2, b);
        assertTrue(protocolRegistry.isRegisteredAddress(a));
        assertTrue(protocolRegistry.isRegisteredAddress(b));

        // Rotate k1 away from a. a is now orphaned.
        protocolRegistry.set(k1, b);
        assertFalse(protocolRegistry.isRegisteredAddress(a));
        assertTrue(protocolRegistry.isRegisteredAddress(b));

        vm.stopPrank();
    }

    function testFuzz_set_same_pair_is_no_op(bytes32 key, address a, address b) public {
        vm.assume(a != address(0) && b != address(0) && a != b);
        // Exclude addresses already wired up by the BaseDotns fixture (registrar,
        // controller, resolvers, etc.) so the single-key accounting this test exercises
        // isn't aliased by unrelated references introduced during setUp.
        vm.assume(!protocolRegistry.isRegisteredAddress(a));
        vm.assume(!protocolRegistry.isRegisteredAddress(b));

        vm.startPrank(owner);
        protocolRegistry.set(key, a);
        protocolRegistry.set(key, a); // no-op
        protocolRegistry.set(key, a); // no-op
        protocolRegistry.set(key, b); // rotate away

        // If set(key, a) had been counted three times, a would still appear registered.
        assertFalse(protocolRegistry.isRegisteredAddress(a));
        assertTrue(protocolRegistry.isRegisteredAddress(b));
        vm.stopPrank();
    }

    function testFuzz_zero_address_never_registered(bytes32 key, address a) public {
        vm.assume(a != address(0));

        assertFalse(protocolRegistry.isRegisteredAddress(address(0)));

        vm.prank(owner);
        protocolRegistry.set(key, a);

        assertFalse(protocolRegistry.isRegisteredAddress(address(0)));
        assertTrue(protocolRegistry.isRegisteredAddress(a));
    }
}
