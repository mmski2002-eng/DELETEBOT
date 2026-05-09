// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IHook } from "./IHook.sol";

interface IERC6551Facet {
    error AccountExecuteRevert();

    function account(uint256 tokenId) external view returns (address);
    function executeAccount(address acc, uint256 tokenId, address to, uint256 value, IHook hook, bytes calldata data) external payable returns (bytes memory result);
}