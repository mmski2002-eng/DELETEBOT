// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;


interface IHook {
    /// @notice Parameters passed to hook functions during account execution
    /// @dev All fields are populated for beforeExecute; success and returnData are only set in afterExecute
    /// @param tokenId The Gotchipus NFT token ID that owns the executing account
    /// @param account The ERC6551 token-bound account address performing the execution
    /// @param caller The address that initiated the executeAccount call
    /// @param to The target address of the execution
    /// @param value The amount of ETH being sent with the execution
    /// @param selector The function selector being called on the target
    /// @param hook The address of the hook contract currently being executed
    /// @param hookData The complete calldata being sent to the target address
    /// @param success Whether the account execution succeeded (only populated in afterExecute)
    /// @param returnData The return data from the execution (only populated in afterExecute)
    struct HookParams {
        uint256 tokenId;
        address account;
        address caller;
        address to;
        uint256 value;
        bytes4 selector;
        address hook;
        bytes hookData;
        // afterExxcute
        bool success;
        bytes returnData;
    }

    /// @notice Permissions that a hook declares it supports
    /// @dev Must accurately reflect which hook functions are implemented
    /// @param beforeExecute True if the hook implements beforeExecute
    /// @param afterExecute True if the hook implements afterExecute
    struct Permissions {
        bool beforeExecute;
        bool afterExecute;
    }

    enum GotchiEvent {
        BeforeExecute,
        AfterExecute
    }
    
    /// @notice Returns the permissions that this hook has
    /// @return permissions A struct of boolean flags indicating which hooks are implemented
    function getHookPermissions() external pure returns (Permissions memory permissions);

    /// @dev MUST return this value on success: bytes4(keccak256("HOOK_SUCCESS"))
    function beforeExecute(HookParams calldata params) external returns (bytes4 magic);

    function afterExecute(HookParams calldata params) external returns (bytes4 magic);
}

