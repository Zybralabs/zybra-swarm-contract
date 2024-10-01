// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

import { Asset, DotcOffer, OfferStruct } from "../structures/DotcStructuresV2.sol";
import { DotcEscrowV2 } from "../DotcEscrowV2.sol";

interface IDotcV2 {
    

    /// External functions

    function makeOffer(
        Asset calldata depositAsset,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer
    ) external;

    function takeOfferFixed(
        uint256 offerId,
        uint256 withdrawalAmountPaid,
        address affiliate
    ) external;

    function takeOfferDynamic(
        uint256 offerId,
        uint256 withdrawalAmountPaid,
        uint256 maximumDepositToWithdrawalRate,
        address affiliate
    ) external;

    function updateOffer(uint256 offerId, OfferStruct calldata updatedOffer) external;

    function cancelOffer(uint256 offerId) external;

    function changeEscrow(DotcEscrowV2 _escrow) external;

    /// View functions
    function currentOfferId() external view returns (uint256);

    function allOffers(uint256 offerId) external view returns (DotcOffer memory);

}
