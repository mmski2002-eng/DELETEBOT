// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { LibGotchiConstants } from "./LibGotchiConstants.sol";

library LibDynamicStates {
    enum GotchiMood {
        HAPPY,
        EXCITED,
        TIRED,
        SAD,
        FOCUSED,
        RESTING
    }

    struct DynamicStates {
        uint8 health;
        uint8 energy;
        uint8 morale;
        uint8 focus;
        GotchiMood currentMood;
        uint32 lastInteraction;
        uint32 lastFeed;
        uint32 lastRest;
        uint32 lastBattle;
        int8 healthModifier;
        int8 energyModifier;
        int8 moraleModifier;
        int8 focusModifier; 
    }

    event StateUpdated(uint256 indexed tokenId, uint8 health, uint8 energy, uint8 morale, uint8 focus);
    event MoodChanged(uint256 indexed tokenId, GotchiMood oldMood, GotchiMood newMood);
    
    function initializeStates(uint32 vitality) internal view returns (DynamicStates memory) {
        uint8 baseHealth = 70 + uint8(vitality / 20);
        uint8 baseEnergy = 60 + uint8(vitality / 25);
        uint8 baseMorale = 80;
        uint8 baseFocus = 50;

        return DynamicStates({
            health: baseHealth > LibGotchiConstants.MAX_STATE ? LibGotchiConstants.MAX_STATE : baseHealth,
            energy: baseEnergy > LibGotchiConstants.MAX_STATE ? LibGotchiConstants.MAX_STATE : baseEnergy,
            morale: baseMorale,
            focus: baseFocus,
            currentMood: GotchiMood.HAPPY,
            lastInteraction: uint32(block.timestamp),
            lastFeed: uint32(block.timestamp),
            lastRest: uint32(block.timestamp),
            lastBattle: 0,
            healthModifier: 0,
            energyModifier: 0,
            moraleModifier: 0,
            focusModifier: 0
        });
    }

    function updateStatesWithDecay(DynamicStates memory states, uint16 vitality) internal view returns (DynamicStates memory) {
        uint32 currentTime = uint32(block.timestamp);
        uint32 timeSinceLastUpdate = currentTime - states.lastInteraction;

        if (timeSinceLastUpdate == 0) return states;

        uint32 hoursElapsed = timeSinceLastUpdate / LibGotchiConstants.HOUR;
        if (hoursElapsed == 0) return states;

        uint256 vitalityFactor = 100 - (vitality > 500 ? 50 : vitality / 10);   // 50-100

        uint8 healthDecay = uint8((hoursElapsed * LibGotchiConstants.HEALTH_DECAY_RATE * vitalityFactor) / 100);
        uint8 energyDecay = uint8((hoursElapsed * LibGotchiConstants.ENERGY_DECAY_RATE * vitalityFactor) / 100);
        uint8 moraleDecay = uint8((hoursElapsed * LibGotchiConstants.MORALE_DECAY_RATE * vitalityFactor) / 100);
        uint8 focusDecay = uint8((hoursElapsed * LibGotchiConstants.FOCUS_DECAY_RATE * vitalityFactor) / 100);

        states.health = states.health > healthDecay ? states.health - healthDecay : LibGotchiConstants.MIN_STATE;
        states.energy = states.energy > energyDecay ? states.energy - energyDecay : LibGotchiConstants.MIN_STATE;
        states.morale = states.morale > moraleDecay ? states.morale - moraleDecay : LibGotchiConstants.MIN_STATE;
        states.focus = states.focus > focusDecay ? states.focus - focusDecay : LibGotchiConstants.MIN_STATE;

        states.currentMood = calculateMood(states);
        
        return states;
    }

    function calculateMood(DynamicStates memory states) internal pure returns (GotchiMood) {
        if (states.energy < 20) return GotchiMood.TIRED;
        if (states.morale < 25 || states.health < 30) return GotchiMood.SAD;
        if (states.focus > 80 && states.energy > 50) return GotchiMood.FOCUSED;
        if (states.energy > 85 && states.morale > 85) return GotchiMood.EXCITED;
        if (states.health > 60 && states.energy > 50 && states.morale > 60) return GotchiMood.HAPPY;
        return GotchiMood.RESTING;
    }

    function performFeed(DynamicStates memory states, uint16 vitality) internal view returns (DynamicStates memory) {
        require(block.timestamp - states.lastFeed >= 8 * LibGotchiConstants.HOUR, "Feed cooldown not met");
        
        states.health = addToState(states.health, 15 + uint8(vitality / 50));
        states.energy = addToState(states.energy, 10);
        states.morale = addToState(states.morale, 5);
        
        states.lastFeed = uint32(block.timestamp);
        states.lastInteraction = uint32(block.timestamp);
        
        states.currentMood = calculateMood(states);
        
        return states;
    }

    function performRest(DynamicStates memory states, uint16 vitality) internal view returns (DynamicStates memory) {
        require(block.timestamp - states.lastRest >= 12 * LibGotchiConstants.HOUR, "Rest cooldown not met");
        
        states.energy = addToState(states.energy, 30 + uint8(vitality / 40));
        states.health = addToState(states.health, 10);
        states.focus = addToState(states.focus, 5);
        
        states.energyModifier = states.energyModifier < 0 ? states.energyModifier / 2 : states.energyModifier;
        states.healthModifier = states.healthModifier < 0 ? states.healthModifier / 2 : states.healthModifier;
        
        states.lastRest = uint32(block.timestamp);
        states.lastInteraction = uint32(block.timestamp);
        
        states.currentMood = GotchiMood.RESTING;
        
        return states;
    }

    function getEffectiveState(uint8 baseValue, int8 modifier_) internal pure returns (uint8) {
        uint256 effective = uint256(baseValue + uint8(modifier_));
        
        if (effective < LibGotchiConstants.MIN_STATE) return LibGotchiConstants.MIN_STATE;
        if (effective > LibGotchiConstants.MAX_STATE) return LibGotchiConstants.MAX_STATE;
        
        return uint8(effective);
    }

    function getEffectiveStates(DynamicStates memory states) internal pure returns (
        uint8 health,
        uint8 energy, 
        uint8 morale,
        uint8 focus
    ) {
        health = getEffectiveState(states.health, states.healthModifier);
        energy = getEffectiveState(states.energy, states.energyModifier);
        morale = getEffectiveState(states.morale, states.moraleModifier);
        focus = getEffectiveState(states.focus, states.focusModifier);
    }

    function needsCare(DynamicStates memory states) internal view returns (bool) {
        (uint8 health, uint8 energy, uint8 morale, ) = getEffectiveStates(states);
        
        return health < 30 || energy < 20 || morale < 25 || 
               (block.timestamp - states.lastInteraction > 2 * LibGotchiConstants.DAY);
    }

    function getMoodName(uint8 mood) internal pure returns (string memory) {
        if (mood == 0) return "Happy";
        if (mood == 1) return "Excited";
        if (mood == 2) return "Tired";
        if (mood == 3) return "Sad";
        if (mood == 4) return "Focused";
        if (mood == 5) return "Resting";
        return "Unknown";
    }

    function addToState(uint8 current, uint8 amount) private pure returns (uint8) {
        uint16 sum = uint16(current) + uint16(amount);
        return sum > LibGotchiConstants.MAX_STATE ? LibGotchiConstants.MAX_STATE : uint8(sum);
    }
}