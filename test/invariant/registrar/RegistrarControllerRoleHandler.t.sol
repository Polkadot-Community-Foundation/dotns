// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {DotnsRegistrarController} from "../../../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";

contract RegistrarControllerRoleHandler is Test {
    DotnsRegistrarController public controller;
    address public owner;
    address[] internal _actors;

    mapping(address account => bool enabled) public ghostWhitelistOperator;

    constructor(DotnsRegistrarController _controller, address _owner, address[] memory actorList) {
        controller = _controller;
        owner = _owner;
        _actors = actorList;
    }

    function setWhitelistOperator(uint256 actorSeed, bool enabled) external {
        address account = _actors[actorSeed % _actors.length];

        vm.prank(owner);
        controller.setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, account, enabled);

        ghostWhitelistOperator[account] = enabled;
    }

    function grantWhitelistOperator(uint256 actorSeed) external {
        address account = _actors[actorSeed % _actors.length];

        vm.prank(owner);
        controller.grantRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, account);

        ghostWhitelistOperator[account] = true;
    }

    function revokeWhitelistOperator(uint256 actorSeed) external {
        address account = _actors[actorSeed % _actors.length];

        vm.prank(owner);
        controller.revokeRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, account);

        ghostWhitelistOperator[account] = false;
    }

    function actors() external view returns (address[] memory actorList) {
        actorList = _actors;
    }
}
