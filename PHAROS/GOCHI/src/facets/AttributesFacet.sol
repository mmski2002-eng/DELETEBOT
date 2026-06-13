// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Modifier, GotchipusInfo } from "../libraries/LibAppStorage.sol";
import { LibAttributes } from "../libraries/LibAttributes.sol";
import { LibDynamicStates } from "../libraries/LibDynamicStates.sol";

contract AttributesFacet is Modifier {
    event SetName(string indexed newName);
    event Pet(uint256 indexed gotchiTokenId);

    function pet(uint256 gotchiTokenId) external {
        require(uint256(s.lastPetTime[gotchiTokenId]) + 1 days <= block.timestamp, "gotchipus already pet");
        require(s.tokenOwners[gotchiTokenId] == msg.sender, "not owner");
        s.lastPetTime[gotchiTokenId] = uint32(block.timestamp);

        GotchipusInfo storage pus = s.ownedGotchipusInfos[msg.sender][gotchiTokenId];

        pus.states.health = LibAttributes.addClampedUint8(pus.states.health, 20);
        pus.states.energy = LibAttributes.addClampedUint8(pus.states.energy, 20);
        pus.states.morale = LibAttributes.addClampedUint8(pus.states.morale, 20);
        pus.states.focus  = LibAttributes.addClampedUint8(pus.states.focus, 20);

        pus.states.lastInteraction = uint32(block.timestamp);
        pus.states.currentMood = LibDynamicStates.GotchiMood.HAPPY;
        pus.leveling.currentExp += 20;
        pus.leveling.totalExp += 20;
        pus.leveling.lastExpGain = uint32(block.timestamp);

        emit Pet(gotchiTokenId);
    }

    function setName(string calldata newName, uint256 gotchiTokenId) external onlyGotchipusOwner(gotchiTokenId) {
        s.ownedGotchipusInfos[msg.sender][gotchiTokenId].name = newName;
        emit SetName(newName);
    }

    function getLastPetTime(uint256 tokenId) external view returns (uint32) {
        return s.lastPetTime[tokenId];
    }

    function getTokenName(uint256 gotchiTokenId) external view returns (string memory) {
        return s.ownedGotchipusInfos[s.tokenOwners[gotchiTokenId]][gotchiTokenId].name;
    }

    function getAttributes(uint256 gotchiTokenId) external view returns (uint32[6] memory) {
        return LibAttributes.calculateAttribute(s.tokenOwners[gotchiTokenId], gotchiTokenId);
    }

    function getSoul(uint256 gotchiTokenId) external view returns (uint32 soul_) {
        soul_ = s.ownedGotchipusInfos[s.tokenOwners[gotchiTokenId]][gotchiTokenId].core.soul.balance;
    }
}