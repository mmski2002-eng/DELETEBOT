// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//******************************************************************************\
//* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
//* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
//*
//* Implementation of a diamond.
//******************************************************************************/

import { WearableLibDiamond } from "./libraries/WearableLibDiamond.sol";
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from  "../interfaces/IDiamondLoupe.sol";

contract WearableDiamond {    
    constructor(address _contractOwner, address _diamondCutFacet, address _diamondLoupeFacet, address _ownershipFacet) payable {
        WearableLibDiamond.setContractOwner(_contractOwner);
        WearableLibDiamond.addDiamondFunctions(_diamondCutFacet, _diamondLoupeFacet, _ownershipFacet);
        WearableLibDiamond.DiamondStorage storage ds = WearableLibDiamond.diamondStorage();
        ds.supportedInterfaces[0xd9b67a26] = true;
    }

    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    fallback() external payable {
        WearableLibDiamond.DiamondStorage storage ds;
        bytes32 position = WearableLibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly {
            ds.slot := position
        }
        // get facet from function selector
        address facet = ds.facetAddressAndSelectorPosition[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: Function does not exist");

        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
             // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
                case 0 {
                    revert(0, returndatasize())
                }
                default {
                    return(0, returndatasize())
                }
        }
    }

    receive() external payable {}
}