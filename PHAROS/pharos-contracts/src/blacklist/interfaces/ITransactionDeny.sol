// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface ITransactionDeny {
    function isBlacklisted(address account) external view returns (bool);
    function addBlacklistedAddresses(address[] memory accounts) external;
    function removeBlacklistedAddresses(address[] memory accounts) external;
    function getBlacklistedAddresses() external view returns (address[] memory);
}
