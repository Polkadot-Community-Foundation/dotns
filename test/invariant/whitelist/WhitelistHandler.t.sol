// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {DotnsNameWhitelist} from "../../../contracts/whitelist/DotnsNameWhitelist.sol";

/// @title WhitelistHandler
/// @notice Drives the whitelist through its lifecycle for the invariant suite, cycling a fixed
///         actor and label set and swallowing expected reverts so the fuzzer keeps exploring.
contract WhitelistHandler is Test {
    DotnsNameWhitelist public immutable WHITELIST;
    address public immutable OWNER;
    address public immutable CONTROLLER;

    address[] internal _actors;
    string[] internal _labels;
    string[] public labelsSeen;
    mapping(bytes32 node => bool tracked) internal _trackedNodes;

    constructor(
        DotnsNameWhitelist whitelist,
        address owner,
        address controller,
        address[] memory actors
    ) {
        WHITELIST = whitelist;
        OWNER = owner;
        CONTROLLER = controller;
        _actors = actors;
        _labels.push("alicebob");
        _labels.push("wonderla");
        _labels.push("carolboy");
        _labels.push("danielle");
    }

    function labelsSeenCount() external view returns (uint256 count) {
        return labelsSeen.length;
    }

    function request(uint256 actorSeed, uint256 labelSeed) external {
        string memory label = _label(labelSeed);
        vm.prank(_actor(actorSeed));
        try WHITELIST.requestName(label) {
            _track(label);
        } catch {}
    }

    function accept(uint256 labelSeed) external {
        vm.prank(OWNER);
        try WHITELIST.accept(_label(labelSeed)) {} catch {}
    }

    function reject(uint256 labelSeed) external {
        vm.prank(OWNER);
        try WHITELIST.reject(_label(labelSeed)) {} catch {}
    }

    function grant(uint256 actorSeed, uint256 labelSeed) external {
        string memory label = _label(labelSeed);
        vm.prank(OWNER);
        try WHITELIST.grantName(label, _actor(actorSeed)) {
            _track(label);
        } catch {}
    }

    function revoke(uint256 labelSeed) external {
        vm.prank(OWNER);
        try WHITELIST.revokeName(_label(labelSeed)) {} catch {}
    }

    function consume(uint256 labelSeed) external {
        string memory label = _label(labelSeed);
        address grantee = WHITELIST.granteeOf(label);
        if (grantee == address(0)) {
            return;
        }
        vm.prank(CONTROLLER);
        try WHITELIST.consume(label, grantee) {} catch {}
    }

    function _actor(uint256 seed) internal view returns (address actor) {
        return _actors[seed % _actors.length];
    }

    function _label(uint256 seed) internal view returns (string memory label) {
        return _labels[seed % _labels.length];
    }

    function _track(string memory label) internal {
        bytes32 node = keccak256(bytes(label));
        if (!_trackedNodes[node]) {
            _trackedNodes[node] = true;
            labelsSeen.push(label);
        }
    }
}
