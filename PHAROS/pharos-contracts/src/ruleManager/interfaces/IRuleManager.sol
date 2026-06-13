// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

interface IRuleManager {
    enum RuleState {
        INIT,
        UPDATED,
        IN_PROVING,
        PROVING_SUCCESS,
        PROVING_FAILURE,
        IN_USE
    }

    struct InferRule {
        uint64 id_; // unque id for InferRule
        bytes4 selctor_; // filter: selctor
        address contract_; // filter: contract
        bytes32 metahash_; // filter: metadata_hash https://solidity-cn.readthedocs.io/zh/develop/metadata.html#id2
        address adder_; // rule adder address
        uint32 type_; // see: infer type define
        RuleState state_; // 0=INIT,1=UPDATED,2=IN_PROVING,3=PROVING_SUCCESS,4=PROVING_FAILURE,5=IN_USE
        bytes code_; // user defined infer rule
    }

    function addRule(uint32 _type, address _addr, bytes4 _selector, bytes32 _metahash, bytes calldata _code)
        external
        returns (uint64);
    function updateRule(uint64 _id, uint32 _type, bytes calldata _code) external returns (uint64);
    function delRule(uint64 _id) external;
    function getAllRules() external view returns (InferRule[] memory);
    function getNextId() external view returns (uint64);
    function getContractRules(address _addr) external view returns (InferRule[] memory);
    function updateProvingResult(uint64[] calldata _successIds, uint64[] calldata _failIds) external;
    function advanceEpoch() external;
    function getImplAddress() external view returns (address);
}
