// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AppStorage, Modifier } from "../libraries/LibAppStorage.sol";
import { IERC6551Executable } from "../interfaces/IERC6551Executable.sol";
import { IHook } from "../interfaces/IHook.sol";
import { LibHooks } from "../libraries/LibHooks.sol";
import { LibSecurity } from "../libraries/LibSecurity.sol";

contract ERC6551Facet is Modifier, ReentrancyGuard {
    error AccountExecuteRevert();

    function account(uint256 tokenId) external view returns (address) {
        return s.accountOwnedByTokenId[tokenId];
    }

    function executeAccount(
        address _account,
        uint256 _tokenId, 
        address _to, 
        uint256 _value, 
        IHook hook,
        bytes calldata _data
    ) external onlyOwnerOrPaymaster(_tokenId) nonReentrant returns (bytes memory result) {
        require(_account != address(0), "ERC6551Facet: Invalid account");
        require(_to != address(0), "ERC6551Facet: Invalid to");

        LibSecurity.validateExecution(_tokenId, msg.sender, _to, _value, _data);

        IHook.HookParams memory params = IHook.HookParams({
            tokenId: _tokenId,
            account: _account,
            caller: msg.sender,
            to: _to,
            value: _value,
            selector: bytes4(_data),
            hook: address(hook),
            hookData: _data,
            success: false,
            returnData: bytes("")
        });

        LibHooks.runHooks(_tokenId, address(hook), IHook.GotchiEvent.BeforeExecute, params);

        bool success;
        (success, result) = _account.call(abi.encodeWithSignature("execute(address,uint256,bytes,uint8)", _to, _value, _data, 0));
        if (success && result.length > 0) {
            (result) = abi.decode(result, (bytes));
        } else if (result.length > 0) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        } else if (!success) {
            revert AccountExecuteRevert();
        }

        params.success = success;
        params.returnData = result;

        LibHooks.runHooks(_tokenId, address(hook), IHook.GotchiEvent.AfterExecute, params);
    }
}