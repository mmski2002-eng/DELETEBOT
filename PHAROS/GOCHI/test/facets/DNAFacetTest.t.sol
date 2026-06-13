// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { DNAFacet } from "../../src/facets/DNAFacet.sol";
import { DNAData } from "../../src/libraries/LibAppStorage.sol";
import { LibDna } from "../../src/libraries/LibDna.sol";
import { LibGotchiConstants } from "../../src/libraries/LibGotchiConstants.sol";

contract DNAFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);

    DNAFacet internal df;
    uint256 constant TOKEN_ID = 0;

    function setUp() public override {
        super.setUp();
        df = DNAFacet(address(diamond));
        vm.deal(ALICE, 200 ether);
        vm.deal(BOB, 200 ether);
    }

    function testRuleVersionDefault() public view {
        assertEq(df.ruleVersion(), 0);
    }

    function testSetRuleVersion() public {
        df.setRuleVersion(5);
        assertEq(df.ruleVersion(), 5);
    }

    function testSetRuleVersionEmitsEvent() public {
        vm.expectEmit(true, false, false, false, address(diamond));
        emit LibDna.SetRuleVersion(3);
        df.setRuleVersion(3);
    }

    function testSetRuleVersionOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        df.setRuleVersion(1);
    }

    function testSetRuleVersionMultipleTimes() public {
        df.setRuleVersion(1);
        assertEq(df.ruleVersion(), 1);
        df.setRuleVersion(255);
        assertEq(df.ruleVersion(), 255);
    }

    function testTokenGeneSeedAfterSummon() public {
        _summonGotchipus(TOKEN_ID);
        DNAData memory dna = df.tokenGeneSeed(TOKEN_ID);
        assertTrue(dna.geneSeed != 0);
    }

    function testTokenGeneSeedBeforeSummon() public {
        vm.prank(ALICE);
        IMintFacet(address(diamond)).mint{value: 0.04 ether}(1);
        DNAData memory dna = df.tokenGeneSeed(TOKEN_ID);
        assertEq(dna.geneSeed, 0);
    }

    function testTokenGeneSeedDifferentTokens() public {
        _summonGotchipus(0);
        _summonGotchipus(1);
        DNAData memory dna0 = df.tokenGeneSeed(0);
        DNAData memory dna1 = df.tokenGeneSeed(1);
        assertTrue(dna0.geneSeed != dna1.geneSeed);
    }

    function testGetGeneAfterSummon() public {
        _summonGotchipus(TOKEN_ID);
        uint256 gene = df.getGene(TOKEN_ID, 0);
        assertLt(gene, 10);
    }

    function testGetGeneConsistency() public {
        _summonGotchipus(TOKEN_ID);
        uint256 gene1 = df.getGene(TOKEN_ID, 0);
        uint256 gene2 = df.getGene(TOKEN_ID, 0);
        assertEq(gene1, gene2);
    }

    function testGetGeneInvalidIndexReverts() public {
        _summonGotchipus(TOKEN_ID);
        vm.expectRevert("Invalid gene index");
        df.getGene(TOKEN_ID, LibGotchiConstants.TOTAL_GENES);
    }

    function testGetGeneMultipleIndices() public {
        _summonGotchipus(TOKEN_ID);
        for (uint256 i; i < 26; i++) {
            uint256 gene = df.getGene(TOKEN_ID, i);
            assertLt(gene, 10);
        }
    }

    function testFuzz_SetRuleVersion(uint8 version) public {
        df.setRuleVersion(version);
        assertEq(df.ruleVersion(), version);
    }

    function testFuzz_GetGeneRange(uint256 index) public {
        _summonGotchipus(TOKEN_ID);
        index = bound(index, 0, LibGotchiConstants.TOTAL_GENES - 1);
        uint256 gene = df.getGene(TOKEN_ID, index);
        assertLt(gene, 10);
    }
}
