// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IMintFacet {
    event Summon(uint256 indexed tokenId);

    struct SummonArgs {
        uint256 gotchipusTokenId;
        string gotchiName;
        address collateralToken;
        uint256 stakeAmount;
        uint8 utc;
        bytes story;
        uint256 preIndex;
    }

    function freeMint() external;

    function mint(uint256 amount) external payable; 

    function summonGotchipus(SummonArgs calldata _args) external payable;

    function addWhitelist(address[] calldata _whitelists, bool[] calldata _isWhitelists) external;

    function paused(bool _paused) external;

    function setSalt(uint256 newSalt) external;
    
    function withdrawETH() external;

}