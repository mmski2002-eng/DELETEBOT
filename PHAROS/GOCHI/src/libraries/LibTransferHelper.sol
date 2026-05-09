// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;


library LibTransferHelper {
    uint256 private constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        assembly {
            let ptr := mload(0x40)

            // transfer(address,uint256)
            mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), and(to, ADDRESS_MASK))
            mstore(add(ptr, 0x24), value)

            let success := call(gas(), and(token, ADDRESS_MASK), 0, ptr, 0x44, ptr, 32)
            let rdsize := returndatasize()

            success := and(
                success,
                or(
                    iszero(rdsize),
                    and(
                        iszero(lt(rdsize, 32)),
                        eq(mload(ptr), 1)
                    )
                )
            )

            if iszero(success) {
                returndatacopy(ptr, 0, rdsize)
                revert(ptr, rdsize)
            }
        }
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        assembly {
            let ptr := mload(0x40)

            // transferFrom(address,address,uint256)
            mstore(ptr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), and(from, ADDRESS_MASK))
            mstore(add(ptr, 0x24), and(to, ADDRESS_MASK))
            mstore(add(ptr, 0x44), value)

            let success := call(gas(), and(token, ADDRESS_MASK), 0, ptr, 0x64, ptr, 32)
            let rdsize := returndatasize()

            success := and(
                success,
                or(
                    iszero(rdsize),
                    and(
                        iszero(lt(rdsize, 32)),
                        eq(mload(ptr), 1)
                    )
                )
            )

            if iszero(success) {
                returndatacopy(ptr, 0, rdsize)
                revert(ptr, rdsize)
            }
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'LibTransferHelper::safeTransferETH: ETH transfer failed');
    }
}