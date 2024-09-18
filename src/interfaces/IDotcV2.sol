// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IDotcManager } from "./IDotcManager.sol";
import { Asset, AssetType, EscrowCallType, ValidityType, OfferStruct, DotcOffer } from "../structures/DotcStructuresV2.sol";

interface IDotcV2 {
   

    // Function Definitions
    function makeOffer(
        Asset calldata depositAsset,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer
    ) external;

    function takeOffer(uint256 offerId, uint256 amountToSend) external;

    function cancelOffer(uint256 offerId) external;

    function updateOffer(
        uint256 offerId,
        uint256 newAmount,
        OfferStruct calldata updatedOffer
    ) external returns (bool status);

    function changeManager(IDotcManager _manager) external returns (bool status);

    function getOffersFromAddress(address account) external view returns (uint256[] memory);

    function getOfferOwner(uint256 offerId) external view returns (address maker);

    function getOffer(uint256 offerId) external view returns (DotcOffer memory offer);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
