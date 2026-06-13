// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title AlwaysRevert
/// @notice Target contract for CallPermit nonce rollback PoC.
///         Has one function that always reverts to simulate a failing subcall,
///         and one function that succeeds to show normal behavior.
contract AlwaysRevert {
    /// @notice Succeeds — used to show nonce increments on success
    function doNothing() external pure returns (bool) {
        return true;
    }

    /// @notice Always reverts — used to trigger nonce rollback
    function alwaysRevert() external pure {
        revert("AlwaysRevert: intentional revert");
    }
}
