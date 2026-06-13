// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IHook } from "@gotchipus/sdk/contracts/interfaces/IHook.sol";
import { BeforeExecuteHook } from "@gotchipus/sdk/contracts/base/BaseHook.sol";

contract WhitelistHook is BeforeExecuteHook {
    mapping(uint256 => mapping(address => bool)) public whitelist;

    event AddressWhitelisted(uint256 indexed tokenId, address indexed target, bool allowed);
    error TargetNotWhitelisted(address target);

    constructor(address _gotchipus) BeforeExecuteHook(_gotchipus) {}

    function setWhitelist(uint256 tokenId, address target, bool allowed) external {
        whitelist[tokenId][target] = allowed;
        emit AddressWhitelisted(tokenId, target, allowed);
    }

    function batchWhitelist(uint256 tokenId, address[] calldata targets) external {
        for (uint256 i = 0; i < targets.length; i++) {
            whitelist[tokenId][targets[i]] = true;
            emit AddressWhitelisted(tokenId, targets[i], true);
        }
    }

    function _beforeExecute(IHook.HookParams calldata params) internal view override {
        if (!whitelist[params.tokenId][params.to]) {
            revert TargetNotWhitelisted(params.to);
        }
    }
}
