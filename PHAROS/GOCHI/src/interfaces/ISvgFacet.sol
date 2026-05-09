// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { LibSvg } from "../libraries/LibSvg.sol";

interface ISvgFacet {
    function getGotchipusSvg(uint256 tokenId) external view returns (string memory gs);
    function getSvg(bytes32 svgType, uint256 id) external view returns (string memory svg);
    function getSliceSvgs(bytes32 svgType, uint256[] calldata ids) external view returns (string[] memory svgs);
    function getSliceSvg(bytes32 svgType, uint256 id) external view returns (string memory svg);
    function storeSvg(bytes calldata svg, LibSvg.SvgItem[] calldata svgItems) external;
    function updateSvg(bytes calldata svg, LibSvg.SvgItem[] calldata svgItems) external;
}