// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice State-dependent target for CallPermit public-signature replay PoC.
/// The signed action is initially valid-looking but reverts until `enabled` flips.
contract TransientTarget {
    bool public enabled;
    mapping(address => uint256) public credits;
    mapping(address => uint256) public spent;

    event Spent(address indexed owner, uint256 amount, address indexed executor);

    function setEnabled(bool value) external {
        enabled = value;
    }

    function mintCredits(address owner, uint256 amount) external {
        credits[owner] += amount;
    }

    function spendCredits(address owner, uint256 amount) external {
        require(enabled, "TransientTarget: disabled");
        require(credits[owner] >= amount, "TransientTarget: insufficient credits");

        credits[owner] -= amount;
        spent[owner] += amount;

        emit Spent(owner, amount, msg.sender);
    }
}
