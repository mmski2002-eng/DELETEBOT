// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Modifier } from "../libraries/LibAppStorage.sol";
import { UserOperation, LibUserOperation } from "../libraries/LibUserOperation.sol";
import { LibMath } from "../libraries/LibMath.sol";
import { IERC6551Facet } from "../interfaces/IERC6551Facet.sol";
import { IHook } from "../interfaces/IHook.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PaymasterFacet is Modifier {
    using SafeERC20 for IERC20;
    using LibUserOperation for UserOperation;
    using LibMath for uint256;

    event Paymaster(address indexed account, address indexed paymasterAddress, address gasToken, uint256 payAmount);
    event TransactionExecuted(address indexed account, bytes data, bytes32 signedHash);
    event PaymasterAction(address indexed paymaster, bool indexed isPaymaster);

    function erc6551Facet() internal view returns (IERC6551Facet eFacet) {
        eFacet = IERC6551Facet(address(this));
    }

    function getNonce(address account) external view returns (uint256) {
        return s.paymaster[account].nonce;
    }

    function isExecutedTx(address account, bytes32 hashTx) external view returns (bool) {
        return s.paymaster[account].extTx[hashTx];
    }

    function isPaymaster(address paymaster) external view returns (bool) {
        return s.isPaymaster[paymaster];
    }

    function addPaymaster(address[] calldata paymasters, bool[] calldata isPaymasters) external onlyOwner {
        require(paymasters.length == isPaymasters.length, "Invalid paymasters");

        for (uint256 i = 0; i < paymasters.length; i++) {
            s.isPaymaster[paymasters[i]] = isPaymasters[i];
            emit PaymasterAction(paymasters[i], isPaymasters[i]);
        }
    }

    function execute(address account, address to, UserOperation calldata userOp) external returns (bool) {
        require(s.isPaymaster[msg.sender], "Only paymaster");
        uint256 startGas = gasleft() + 21000 + msg.data.length * 8;
        require(startGas >= userOp.gasLimit, "Not enough gas provided");
        require(ValidateSignature(userOp), "Invalid signature");

        bytes32 signHash = getSignHash(userOp);
        require(!s.paymaster[msg.sender].extTx[signHash], "Tx already exists");
        require(s.paymaster[msg.sender].nonce == userOp.nonce, "Nonce to low/high");
        s.paymaster[msg.sender].nonce += 1;
        s.paymaster[msg.sender].extTx[signHash] = true;

        paymasterPrepayment(account, startGas, userOp);

        bool success;
        bytes memory result = erc6551Facet().executeAccount(
            account,
            userOp.tokenId,
            to,
            userOp.value,
            IHook(address(0)),
            userOp.data
        );
        if (result.length > 0) {
            require(abi.decode(result, (bool)), "Paymaster transfer failed");
            success = true;
        }
        
        emit TransactionExecuted(account, userOp.data, signHash);
        return success;
    }


    function ValidateSignature(UserOperation calldata userOp) internal view returns (bool) {
        return SignatureChecker.isValidSignatureNow(
            s.tokenOwners[userOp.tokenId], 
            getSignHash(userOp), 
            userOp.signature
        );
    }
    
    function getSignHash(UserOperation calldata userOp) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                userOp.hash()
            )
        );
    }

    function paymasterPrepayment(
        address account, 
        uint256 startGas,
        UserOperation calldata userOp
    ) internal {
        if (userOp.gasPrice > 0) {
            address paymasterAddress =  userOp.gasPaymaster == address(0) ? msg.sender : userOp.gasPaymaster;
            
            uint256 payAmount;
            if (userOp.gasToken == address(0)) {
                uint256 gasConsumed = startGas - gasleft() + 23000;
                payAmount = gasConsumed.min(userOp.gasLimit) * userOp.gasPrice.min(tx.gasprice);
                erc6551Facet().executeAccount(
                    account,
                    userOp.tokenId,
                    paymasterAddress,
                    payAmount,
                    IHook(address(0)),
                    ""
                );
            } else {
                uint256 gasConsumed = startGas - gasleft() + 37500;
                // get token gas price from dex oracle
                uint256 tokenGasPrice = 1; 
                payAmount = gasConsumed.min(userOp.gasLimit) * userOp.gasPrice.min(tokenGasPrice);
                bytes memory payData = abi.encodeWithSelector(IERC20.transfer.selector, paymasterAddress, payAmount);
                bytes memory result = erc6551Facet().executeAccount(
                    account,
                    userOp.tokenId,
                    paymasterAddress,
                    0,
                    IHook(address(0)),
                    payData
                );
                if (result.length > 0) {
                    require(abi.decode(result, (bool)), "Paymaster transfer failed");
                }
            }

            emit Paymaster(account, paymasterAddress, userOp.gasToken, payAmount);
        }
    }

}