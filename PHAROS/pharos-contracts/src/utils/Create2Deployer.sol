// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

/**
 * @title Create2Deployer
 * @notice Utility contract for deploying contracts using CREATE2 opcode
 * @dev This contract allows deterministic deployment of contracts using CREATE2
 *      which is useful for upgradeable contracts and predicting contract addresses
 */
contract Create2Deployer {
    event ContractDeployed(address indexed deployedAddress, bytes32 indexed salt);

    /**
     * @notice Deploy a contract using CREATE2
     * @param bytecode The creation code of the contract to deploy
     * @param salt A unique value to determine the deployed address
     * @return deployedAddress The address of the deployed contract
     */
    function deploy(bytes memory bytecode, bytes32 salt) external returns (address deployedAddress) {
        assembly {
            deployedAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

            // Use revert if deployment failed
            if iszero(extcodesize(deployedAddress)) { revert(0, 0) }
        }

        emit ContractDeployed(deployedAddress, salt);
    }

    /**
     * @notice Deploy a contract with constructor arguments using CREATE2
     * @param bytecode The creation code of the contract to deploy
     * @param salt A unique value to determine the deployed address
     * @param args The encoded constructor arguments
     * @return deployedAddress The address of the deployed contract
     */
    function deployWithArgs(bytes memory bytecode, bytes32 salt, bytes memory args)
        external
        returns (address deployedAddress)
    {
        bytes memory fullBytecode = bytes.concat(bytecode, args);

        assembly {
            deployedAddress := create2(0, add(fullBytecode, 0x20), mload(fullBytecode), salt)

            if iszero(extcodesize(deployedAddress)) { revert(0, 0) }
        }

        emit ContractDeployed(deployedAddress, salt);
    }

    /**
     * @notice Compute the address of a contract that would be deployed using CREATE2
     * @param deployer The address that will deploy the contract
     * @param salt The salt used for deployment
     * @param bytecodeHash The hash of the contract bytecode
     * @return The predicted address
     */
    function computeAddress(address deployer, bytes32 salt, bytes32 bytecodeHash) external pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash)))));
    }

    /**
     * @notice Get the creation code hash of a contract
     * @param bytecode The creation code
     * @return The hash of the bytecode
     */
    function getBytecodeHash(bytes memory bytecode) external pure returns (bytes32) {
        return keccak256(bytecode);
    }
}
