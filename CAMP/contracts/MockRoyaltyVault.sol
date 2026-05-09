// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title MockRoyaltyVault — Local test replica of the vulnerable IpRoyaltyVault
/// @notice Mimics the exact vulnerability: updateVaultBalance() has NO access control
/// @dev Used for Hardhat-based PoC testing (without Foundry)
contract MockRoyaltyVault {
    using EnumerableSet for EnumerableSet.AddressSet;

    string public name = "Test Royalty Token";
    string public symbol = "RT";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    EnumerableSet.AddressSet private _revenueTokens;
    mapping(address => uint256) private _vaultAccBalances;
    mapping(address => mapping(address => int256)) private _claimerRevenueDebt;

    // ──────────────────────────────────────────────
    //  TOKEN LOGIC (simplified ERC-20)
    // ──────────────────────────────────────────────

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    // ──────────────────────────────────────────────
    //  VULNERABLE CODE (identical to production)
    // ──────────────────────────────────────────────

    /// @notice VULNERABLE: No access control!
    /// @dev The comment in production code literally says:
    ///      "// In production, you'd want more sophisticated access control"
    function updateVaultBalance(address token, uint256 amount) external {
        require(amount > 0, "ZeroAmount");
        _revenueTokens.add(token);
        _vaultAccBalances[token] += amount;

        emit RevenueTokenAddedToVault(token, amount);
    }

    /// @notice Claim revenue with debt tracking (simplified)
    function claimRevenue(address claimer, address token) external returns (uint256) {
        uint256 pending = _claimableRevenueScaled(claimer, token) / totalSupply;
        require(pending > 0, "NoClaimableRevenue");

        _claimerRevenueDebt[token][claimer] += int256(pending) * int256(totalSupply);

        emit RevenueClaimed(claimer, token, pending);
        return pending;
    }

    /// @notice View function for claimable revenue
    function claimableRevenue(address claimer, address token) external view returns (uint256) {
        if (totalSupply == 0) return 0;
        return _claimableRevenueScaled(claimer, token) / totalSupply;
    }

    // ──────────────────────────────────────────────
    //  VIEW FUNCTIONS
    // ──────────────────────────────────────────────

    function vaultAccBalance(address token) external view returns (uint256) {
        return _vaultAccBalances[token];
    }

    function claimerRevenueDebt(address claimer, address token) external view returns (int256) {
        return _claimerRevenueDebt[token][claimer];
    }

    function getRevenueTokens() external view returns (address[] memory) {
        return _revenueTokens.values();
    }

    function revenueTokensLength() external view returns (uint256) {
        return _revenueTokens.length();
    }

    // ──────────────────────────────────────────────
    //  INTERNAL
    // ──────────────────────────────────────────────

    function _claimableRevenueScaled(address claimer, address token) internal view returns (uint256) {
        uint256 accBalance = _vaultAccBalances[token];
        uint256 userBalance = balanceOf[claimer];
        int256 debt = _claimerRevenueDebt[token][claimer];

        int256 pendingScaled = int256(accBalance * userBalance) - debt;
        if (pendingScaled < 0) return 0;
        return uint256(pendingScaled);
    }

    // ──────────────────────────────────────────────
    //  EVENTS
    // ──────────────────────────────────────────────

    event RevenueTokenAddedToVault(address indexed token, uint256 amount);
    event RevenueClaimed(address indexed claimer, address indexed token, uint256 amount);
}

// ─────────────────────────────────────────────────
//  EnumerableSet Library (minimal, inline)
// ─────────────────────────────────────────────────

library EnumerableSet {
    struct AddressSet {
        address[] _values;
        mapping(address => uint256) _indexes;
    }

    function add(AddressSet storage set, address value) internal returns (bool) {
        if (!contains(set, value)) {
            set._values.push(value);
            set._indexes[value] = set._values.length;
            return true;
        }
        return false;
    }

    function remove(AddressSet storage set, address value) internal returns (bool) {
        uint256 valueIndex = set._indexes[value];
        if (valueIndex == 0) return false;

        uint256 toDeleteIndex = valueIndex - 1;
        uint256 lastIndex = set._values.length - 1;

        if (toDeleteIndex != lastIndex) {
            address lastValue = set._values[lastIndex];
            set._values[toDeleteIndex] = lastValue;
            set._indexes[lastValue] = valueIndex;
        }

        set._values.pop();
        delete set._indexes[value];
        return true;
    }

    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return set._indexes[value] != 0;
    }

    function length(AddressSet storage set) internal view returns (uint256) {
        return set._values.length;
    }

    function values(AddressSet storage set) internal view returns (address[] memory) {
        return set._values;
    }
}
