// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Minimally extracted IpRoyaltyVault interface for PoC
/// @notice Only the functions needed for the exploit demonstration
interface IIpRoyaltyVault {
    /// @notice VULNERABLE: No access control on this function
    function updateVaultBalance(address token, uint256 amount) external;

    /// @notice Claim revenue for a single token
    function claimRevenue(address claimer, address token) external returns (uint256);

    /// @notice Get claimable revenue
    function claimableRevenue(address claimer, address token) external view returns (uint256);

    /// @notice Get vault accumulated balance for a token
    function vaultAccBalance(address token) external view returns (uint256);

    /// @notice Get revenue debt for a claimer
    function claimerRevenueDebt(address claimer, address token) external view returns (int256);

    /// @notice Get all revenue tokens tracked
    function getRevenueTokens() external view returns (address[] memory);

    /// @notice Balance of royalty tokens for a user
    function balanceOf(address account) external view returns (uint256);

    /// @notice Total supply of royalty tokens
    function totalSupply() external view returns (uint256);
}
