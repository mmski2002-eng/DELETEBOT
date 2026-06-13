// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, LibAppStorage } from "./LibAppStorage.sol";
import { IHook } from "../interfaces/IHook.sol";
import { CustomRevert } from "./CustomRevert.sol";

library LibHooks {
    using LibHooks for IHook;
    using CustomRevert for bytes4;

    bytes4 internal constant HOOK_SUCCESS = bytes4(keccak256("HOOK_SUCCESS"));

    error HookPermissionsNotValid(address hook);
    error HookNotFound(uint256 tokenId, address hook);
    error HookCallFailed();
    error InvalidHookResponse();

    event HookExecuted(uint256 indexed tokenId, address indexed hook, IHook.GotchiEvent eventType, bool success);
    event HookExecutionFailed(uint256 indexed tokenId, address indexed hook, IHook.GotchiEvent eventType, bytes reason);

    function validateHookPermissions(IHook hook, IHook.Permissions memory permissions) internal pure {
        IHook.Permissions memory actualPermissions = hook.getHookPermissions();
        
        if ((permissions.beforeExecute && !actualPermissions.beforeExecute) || 
            (permissions.afterExecute && !actualPermissions.afterExecute)) {
            HookPermissionsNotValid.selector.revertWith(address(hook));
        }
        
        if (!actualPermissions.beforeExecute && !actualPermissions.afterExecute) {
            HookPermissionsNotValid.selector.revertWith(address(hook));
        }
    }

    function validateHookForEvent(IHook hook, IHook.GotchiEvent eventType) internal pure {
        IHook.Permissions memory permissions = hook.getHookPermissions();

        if (eventType == IHook.GotchiEvent.BeforeExecute) {
            if (!permissions.beforeExecute) {
                HookPermissionsNotValid.selector.revertWith(address(hook));
            }
        } else if (eventType == IHook.GotchiEvent.AfterExecute) {
            if (!permissions.afterExecute) {
                HookPermissionsNotValid.selector.revertWith(address(hook));
            }
        }
    }

    function isValidHookAddress(uint256 tokenId, IHook hook) internal view returns (bool) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        return s.isValidHook[tokenId][address(hook)];
    }

    function runHooks(
        uint256 tokenId,
        address hook,
        IHook.GotchiEvent eventType,
        IHook.HookParams memory params
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (hook != address(0)) {
            if (!s.isValidHook[tokenId][hook]) {
                revert HookNotFound(tokenId, hook);
            }

            IHook.Permissions memory perms = IHook(hook).getHookPermissions();
            if (eventType == IHook.GotchiEvent.BeforeExecute && !perms.beforeExecute) {
                return;
            }
            if (eventType == IHook.GotchiEvent.AfterExecute && !perms.afterExecute) {
                return;
            }

            _executeHook(tokenId, hook, eventType, params);
        }
    }

    function _executeHook(
        uint256 tokenId,
        address hook,
        IHook.GotchiEvent eventType,
        IHook.HookParams memory params
    ) private {
        bytes4 magic;
        bool success;
        bytes memory reason;

        if (eventType == IHook.GotchiEvent.BeforeExecute) {
            try IHook(hook).beforeExecute(params) returns (bytes4 _magic) {
                magic = _magic;
                success = true;
            } catch (bytes memory _reason) {
                reason = _reason;
            }
        } else {
            try IHook(hook).afterExecute(params) returns (bytes4 _magic) {
                magic = _magic;
                success = true;
            } catch (bytes memory _reason) {
                reason = _reason;
            }
        }

        if (success) {
            if (magic != HOOK_SUCCESS) {
                revert InvalidHookResponse();
            }
            emit HookExecuted(tokenId, hook, eventType, true);
        } else {
            emit HookExecutionFailed(tokenId, hook, eventType, reason);
            bytes4 functionSelector = eventType == IHook.GotchiEvent.BeforeExecute
                ? IHook.beforeExecute.selector
                : IHook.afterExecute.selector;
            CustomRevert.bubbleUpAndRevertWith(hook, functionSelector, HookCallFailed.selector);
        }
    }

    function runHooksWithGasLimit(
        uint256 tokenId,
        address hook,
        IHook.GotchiEvent eventType,
        IHook.HookParams memory params,
        uint256 gasLimit
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (hook != address(0)) {
            if (!s.isValidHook[tokenId][hook]) {
                revert HookNotFound(tokenId, hook);
            }

            _executeHookWithGasLimit(tokenId, hook, eventType, params, gasLimit);
        }
    }

    function _executeHookWithGasLimit(
        uint256 tokenId,
        address hook,
        IHook.GotchiEvent eventType,
        IHook.HookParams memory params,
        uint256 gasLimit
    ) private {
        bytes memory callData;
        
        if (eventType == IHook.GotchiEvent.BeforeExecute) {
            callData = abi.encodeWithSelector(IHook.beforeExecute.selector, params);
        } else {
            callData = abi.encodeWithSelector(IHook.afterExecute.selector, params);
        }

        (bool success, bytes memory returnData) = hook.call{gas: gasLimit}(callData);

        if (success && returnData.length >= 32) {
            bytes4 magic = abi.decode(returnData, (bytes4));
            if (magic != HOOK_SUCCESS) {
                revert InvalidHookResponse();
            }
            emit HookExecuted(tokenId, hook, eventType, true);
        } else {
            emit HookExecutionFailed(tokenId, hook, eventType, returnData);
            bytes4 functionSelector = eventType == IHook.GotchiEvent.BeforeExecute
                ? IHook.beforeExecute.selector
                : IHook.afterExecute.selector;
            CustomRevert.bubbleUpAndRevertWith(hook, functionSelector, HookCallFailed.selector);
        }
    }
}

