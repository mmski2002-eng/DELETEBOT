// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IHook } from "../interfaces/IHook.sol";

abstract contract BaseHook is IHook {
    bytes4 public constant HOOK_SUCCESS = bytes4(keccak256("HOOK_SUCCESS"));
    address public immutable gotchipus;

    error NotGotchipus();
    error HookNotImplemented();

    constructor(address _gotchipus) {
        gotchipus = _gotchipus;
    }

    modifier onlyGotchipus() {
        if (msg.sender != gotchipus) {
            revert NotGotchipus();
        }
        _;
    }

    function getHookPermissions() external pure virtual returns (Permissions memory) {
        return Permissions({
            beforeExecute: false,
            afterExecute: false
        });
    }

    function beforeExecute(HookParams calldata params) external virtual onlyGotchipus returns (bytes4) {
        _beforeExecute(params);
        return HOOK_SUCCESS;
    }

    function afterExecute(HookParams calldata params) external virtual onlyGotchipus returns (bytes4) {
        _afterExecute(params);
        return HOOK_SUCCESS;
    }

    function _beforeExecute(HookParams calldata params) internal virtual {}
    function _afterExecute(HookParams calldata params) internal virtual {}
}

abstract contract BeforeExecuteHook is BaseHook {
    constructor(address _gotchipus) BaseHook(_gotchipus) {}

    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({
            beforeExecute: true,
            afterExecute: false
        });
    }

    function afterExecute(HookParams calldata) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }
}

abstract contract AfterExecuteHook is BaseHook {
    constructor(address _gotchipus) BaseHook(_gotchipus) {}

    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({
            beforeExecute: false,
            afterExecute: true
        });
    }

    function beforeExecute(HookParams calldata) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }
}

abstract contract FullHook is BaseHook {
    constructor(address _gotchipus) BaseHook(_gotchipus) {}

    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({
            beforeExecute: true,
            afterExecute: true
        });
    }
}
