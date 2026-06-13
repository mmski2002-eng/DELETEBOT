// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal local model of Moonbeam CallPermit relevant to replay analysis.
/// It intentionally reverts when the target call reverts, so the nonce increment
/// is rolled back in the same EVM frame.
contract MockCallPermit {
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "CallPermit(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 nonce,uint256 deadline)"
    );

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    mapping(address => uint256) public nonces;

    event Dispatched(address indexed dispatcher, address indexed from, address indexed to, bytes data);

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Call Permit Precompile")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function dispatch(
        address from,
        address to,
        uint256 value,
        bytes memory data,
        uint64 gaslimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes memory output) {
        require(block.timestamp <= deadline, "Permit expired");

        uint256 nonce = nonces[from];
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, from, to, value, keccak256(data), gaslimit, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0) && signer == from, "Invalid permit");

        nonces[from] = nonce + 1;

        (bool ok, bytes memory result) = to.call{value: value, gas: gaslimit}(data);
        if (!ok) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit Dispatched(msg.sender, from, to, data);
        return result;
    }
}
