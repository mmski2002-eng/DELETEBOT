// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Modifier } from "../libraries/LibAppStorage.sol";
import { LibHooks } from "../libraries/LibHooks.sol";
import { LibGotchiConstants } from "../libraries/LibGotchiConstants.sol";
import { IHook } from "../interfaces/IHook.sol";

contract HooksFacet is Modifier {
    event HookAdded(uint256 indexed tokenId, IHook.GotchiEvent indexed eventType, address indexed hook);
    event HookRemoved(uint256 indexed tokenId, IHook.GotchiEvent indexed eventType, address indexed hook);
    event HookApprovalChanged(uint256 indexed tokenId, address indexed hook, bool approved);

    error HookAlreadyExists(uint256 tokenId, address hook);
    error HookNotFound(uint256 tokenId, address hook);
    error InvalidHookAddress();
    error HookDoesNotSupportEvent(address hook, IHook.GotchiEvent eventType);
    error MaxHooksPerEventReached(uint256 tokenId, IHook.GotchiEvent eventType);

    function addHook(uint256 tokenId, IHook.GotchiEvent eventType, IHook hook) external onlyGotchipusOwner(tokenId) {
        if (address(hook) == address(0)) {
            revert InvalidHookAddress();
        }

        if (s.isValidHook[tokenId][address(hook)]) {
            revert HookAlreadyExists(tokenId, address(hook));
        }

        if (s.tokenHooksByEvent[tokenId][eventType].length >= LibGotchiConstants.MAX_HOOKS_PER_EVENT) {
            revert MaxHooksPerEventReached(tokenId, eventType);
        }

        _validateHookSupportsEvent(hook, eventType);

        s.tokenHooksByEvent[tokenId][eventType].push(address(hook));
        s.hookIndex[tokenId][eventType][address(hook)] = s.tokenHooksByEvent[tokenId][eventType].length;
        s.isValidHook[tokenId][address(hook)] = true;

        emit HookAdded(tokenId, eventType, address(hook));
    }

    function addHookToEvents(
        uint256 tokenId,
        IHook hook,
        bool forBeforeExecute,
        bool forAfterExecute
    ) external onlyGotchipusOwner(tokenId) {
        if (address(hook) == address(0)) {
            revert InvalidHookAddress();
        }

        if (s.isValidHook[tokenId][address(hook)]) {
            revert HookAlreadyExists(tokenId, address(hook));
        }

        IHook.Permissions memory permissions = hook.getHookPermissions();

        if (forBeforeExecute) {
            if (!permissions.beforeExecute) {
                revert HookDoesNotSupportEvent(address(hook), IHook.GotchiEvent.BeforeExecute);
            }
            if (s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.BeforeExecute].length >= LibGotchiConstants.MAX_HOOKS_PER_EVENT) {
                revert MaxHooksPerEventReached(tokenId, IHook.GotchiEvent.BeforeExecute);
            }

            s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.BeforeExecute].push(address(hook));
            uint256 len = s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.BeforeExecute].length;
            s.hookIndex[tokenId][IHook.GotchiEvent.BeforeExecute][address(hook)] = len;
            emit HookAdded(tokenId, IHook.GotchiEvent.BeforeExecute, address(hook));
        }

        if (forAfterExecute) {
            if (!permissions.afterExecute) {
                revert HookDoesNotSupportEvent(address(hook), IHook.GotchiEvent.AfterExecute);
            }
            if (s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.AfterExecute].length >= LibGotchiConstants.MAX_HOOKS_PER_EVENT) {
                revert MaxHooksPerEventReached(tokenId, IHook.GotchiEvent.AfterExecute);
            }

            s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.AfterExecute].push(address(hook));
            uint256 len = s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.AfterExecute].length;
            s.hookIndex[tokenId][IHook.GotchiEvent.AfterExecute][address(hook)] = len;
            emit HookAdded(tokenId, IHook.GotchiEvent.AfterExecute, address(hook));
        }

        s.isValidHook[tokenId][address(hook)] = true;
    }

    function removeHook(uint256 tokenId, IHook.GotchiEvent eventType, IHook hook) external onlyGotchipusOwner(tokenId) {
        address hookAddr = address(hook);
        uint256 index = s.hookIndex[tokenId][eventType][hookAddr];
        
        if (index == 0) {
            revert HookNotFound(tokenId, hookAddr);
        }

        address[] storage hooks = s.tokenHooksByEvent[tokenId][eventType];
        uint256 lastIndex = hooks.length;

        if (index != lastIndex) {
            address lastHook = hooks[lastIndex - 1];
            hooks[index - 1] = lastHook;
            s.hookIndex[tokenId][eventType][lastHook] = index;
        }

        hooks.pop();
        delete s.hookIndex[tokenId][eventType][hookAddr];

        bool stillRegistered = _isHookRegisteredInAnyEvent(tokenId, hookAddr);
        if (!stillRegistered) {
            s.isValidHook[tokenId][hookAddr] = false;
        }

        emit HookRemoved(tokenId, eventType, hookAddr);
    }

    function removeHookCompletely(uint256 tokenId, IHook hook) external onlyGotchipusOwner(tokenId) {
        if (!s.isValidHook[tokenId][address(hook)]) {
            revert HookNotFound(tokenId, address(hook));
        }

        bool wasBefore = s.hookIndex[tokenId][IHook.GotchiEvent.BeforeExecute][address(hook)] != 0;
        bool wasAfter = s.hookIndex[tokenId][IHook.GotchiEvent.AfterExecute][address(hook)] != 0;

        _removeHookFromArray(tokenId, IHook.GotchiEvent.BeforeExecute, address(hook));
        _removeHookFromArray(tokenId, IHook.GotchiEvent.AfterExecute, address(hook));

        s.isValidHook[tokenId][address(hook)] = false;

        if (wasBefore) {
            emit HookRemoved(tokenId, IHook.GotchiEvent.BeforeExecute, address(hook));
        }
        if (wasAfter) {
            emit HookRemoved(tokenId, IHook.GotchiEvent.AfterExecute, address(hook));
        }
    }

    function setHookApproval(uint256 tokenId, IHook hook, bool approved) external onlyGotchipusOwner(tokenId) {
        if (!_isHookRegisteredInAnyEvent(tokenId, address(hook))) {
            revert HookNotFound(tokenId, address(hook));
        }

        s.isValidHook[tokenId][address(hook)] = approved;

        emit HookApprovalChanged(tokenId, address(hook), approved);
    }

    function getHooks(uint256 tokenId, IHook.GotchiEvent eventType) external view returns (address[] memory hooks) {
        hooks = s.tokenHooksByEvent[tokenId][eventType];
    }

    function getActiveHooks(uint256 tokenId, IHook.GotchiEvent eventType) external view returns (address[] memory activeHooks) {
        address[] storage allHooks = s.tokenHooksByEvent[tokenId][eventType];
        uint256 len = allHooks.length;
        
        uint256 activeCount = 0;
        for (uint256 i = 0; i < len; i++) {
            if (s.isValidHook[tokenId][allHooks[i]]) {
                activeCount++;
            }
        }

        activeHooks = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < len; i++) {
            if (s.isValidHook[tokenId][allHooks[i]]) {
                activeHooks[index] = allHooks[i];
                index++;
            }
        }
    }

    function isHookValid(uint256 tokenId, address hook) external view returns (bool isValid) {
        isValid = s.isValidHook[tokenId][hook];
    }

    function getHookCount(uint256 tokenId, IHook.GotchiEvent eventType) external view returns (uint256 count) {
        count = s.tokenHooksByEvent[tokenId][eventType].length;
    }

    function _validateHookSupportsEvent(IHook hook, IHook.GotchiEvent eventType) internal pure {
        IHook.Permissions memory permissions = hook.getHookPermissions();

        if (eventType == IHook.GotchiEvent.BeforeExecute) {
            if (!permissions.beforeExecute) {
                revert HookDoesNotSupportEvent(address(hook), eventType);
            }
        } else if (eventType == IHook.GotchiEvent.AfterExecute) {
            if (!permissions.afterExecute) {
                revert HookDoesNotSupportEvent(address(hook), eventType);
            }
        }
    }

    function _isHookRegisteredInAnyEvent(uint256 tokenId, address hook) internal view returns (bool) {
        address[] storage beforeHooks = s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.BeforeExecute];
        for (uint256 i = 0; i < beforeHooks.length; i++) {
            if (beforeHooks[i] == hook) return true;
        }

        address[] storage afterHooks = s.tokenHooksByEvent[tokenId][IHook.GotchiEvent.AfterExecute];
        for (uint256 i = 0; i < afterHooks.length; i++) {
            if (afterHooks[i] == hook) return true;
        }

        return false;
    }

    function _removeHookFromArray(
        uint256 tokenId,
        IHook.GotchiEvent eventType,
        address hook
    ) internal {
        uint256 index = s.hookIndex[tokenId][eventType][hook];
        if (index == 0) return;

        address[] storage hooks = s.tokenHooksByEvent[tokenId][eventType];
        uint256 lastIndex = hooks.length;

        if (index != lastIndex) {
            address lastHook = hooks[lastIndex - 1];
            hooks[index - 1] = lastHook;
            s.hookIndex[tokenId][eventType][lastHook] = index;
        }

        hooks.pop();
        delete s.hookIndex[tokenId][eventType][hook];
    }
}