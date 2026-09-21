// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {console} from "forge-std/Script.sol";
import {WireDeployments} from "./WireDeployments.s.sol";

import {DotnsCostModelRegistry} from "../../contracts/pop/DotnsCostModelRegistry.sol";
import {DotnsProtocolRegistry} from "../../contracts/registry/DotnsProtocolRegistry.sol";

/// @title VerifyProduction
/// @notice Read-only re-run of the WireDeployments verification against a network
///         whose ownership has been handed over, plus the release and TLD it declares.
/// @dev Broadcasts nothing. Run without --broadcast:
///      `forge script scripts/deploy/VerifyProduction.s.sol:VerifyProduction
///       --sig 'verify(address,string,string)' <owner> <release> <tld suffix>`.
/// @custom:security-contact admin@parity.io
contract VerifyProduction is WireDeployments {
    function verify(
        address expectedOwner,
        string calldata releaseTag,
        string calldata tldSuffix
    )
        external
    {
        initDeployment(networkFolder(), vm.toString(block.chainid));
        Addresses memory addr = _loadAddresses();

        _verifyDeployment(addr, expectedOwner);
        require(
            DotnsCostModelRegistry(addr.costModelRegistry).owner() == expectedOwner,
            "CostModelRegistry: wrong owner"
        );

        DotnsProtocolRegistry registry = DotnsProtocolRegistry(addr.protocolRegistry);
        require(
            keccak256(bytes(registry.protocolVersion())) == keccak256(bytes(releaseTag)),
            "ProtocolVersion: mismatch"
        );
        require(keccak256(bytes(registry.tld())) == keccak256(bytes(tldSuffix)), "TLD: mismatch");

        console.log("=== Production verification complete ===");
    }
}
