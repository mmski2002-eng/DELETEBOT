// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, TraitsOffset } from "./libraries/LibAppStorage.sol";
import { LibDiamond } from "./libraries/LibDiamond.sol";
import { LibSvg } from "./libraries/LibSvg.sol";
import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from  "./interfaces/IDiamondLoupe.sol";
import { IERC173 } from "./interfaces/IERC173.sol";
import { IERC165} from "./interfaces/IERC165.sol";


contract InitDiamond {
    AppStorage internal s;

    struct Args {
        string name;
        string symbol;
        string baseUri;
        uint8 createUtcHour;
        TraitsOffset[] traitsOffset;
        address erc6551Registry;
        address erc6551AccountImplementation;
        bytes32[8] svgTypes;
        uint256 salt;
    }

    function init(Args calldata _args) external {
        s.name = _args.name;
        s.symbol = _args.symbol;
        s.baseUri = _args.baseUri;
        s.createWorldTime = uint32(block.timestamp);
        s.createTimeForTimeHour = _args.createUtcHour;
        s.traitsOffset = _args.traitsOffset;
        s.erc6551Registry = _args.erc6551Registry;
        s.erc6551Implementation = _args.erc6551AccountImplementation;
        s.globalSalt = _args.salt;

        for (uint256 i = 0; i < _args.svgTypes.length; i++) {
            s.svgTypeBytes32[uint8(i)] = _args.svgTypes[i];
        }

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        // erc165
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
        // erc1155
        ds.supportedInterfaces[0xd9b67a26] = true;

    }
}