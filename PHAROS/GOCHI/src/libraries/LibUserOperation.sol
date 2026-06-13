// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

struct UserOperation {
    address from;
    uint256 value;
    bytes data;
    uint256 tokenId;
    uint256 nonce;
    uint256 gasPrice;
    uint256 gasLimit;
    address gasToken;
    address gasPaymaster;
    bytes signature;
}

library LibUserOperation {
    function hash(UserOperation calldata userOp) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                bytes1(0x19),
                bytes1(0),
                userOp.from,
                userOp.value,
                userOp.data,
                userOp.tokenId,
                block.chainid,
                userOp.nonce,
                userOp.gasPrice,
                userOp.gasLimit,
                userOp.gasToken,
                userOp.gasPaymaster
            )
        );
    }
}