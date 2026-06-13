// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

interface IChainConfig {
    struct Config {
        string key;
        string value;
    }

    struct ConfigCheckpoint {
        uint64 blockNum;
        uint64 effectiveBlockNum;
        Config[] configs;
    }

    function getConfig(string memory key) external view returns (string memory);
    function getConfigs() external view returns (Config[] memory);
    function getPendingConfigs() external view returns (Config[] memory);
    function setConfig(string[] memory keys, string[] memory values) external;
    function addPendingConfig(string[] memory keys, string[] memory values) external;
    function getImplAddress() external view returns (address);
}
