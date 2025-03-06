// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.20;

import { Initializable, Receiver, SafeTransferLib, FixedPointMathLib, IERC721, IERC1155 } from "./exports/ExternalExports.sol";

import { AssetHelper } from "./helpers/AssetHelper.sol";
import { OfferHelper } from "./helpers/OfferHelper.sol";
import { DotcOfferHelper } from "./helpers/DotcOfferHelper.sol";
import { DotcEscrowV2 } from "./DotcEscrowV2.sol";
import { DotcManagerV2 } from "./DotcManagerV2.sol";

import { Asset, AssetType, OfferFillType, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType } from "./structures/DotcStructuresV2.sol";



interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}



/// @title Errors related to the Dotc contract
/// @notice Provides error messages for various failure conditions related to Offers and Assets handling

/**
 * @notice Thrown when the deposit-to-withdrawal rate calculation overflows.
 */
error DepositToWithdrawalRateOverflow();

/**
 * @notice Thrown when the Block offer paid partially.
 */
error BlockOfferShouldBePaidFully(uint256 withdrawalAmountPaid);

/**
 * @notice Thrown when called not correct function.
 * This could be in two cases:
 * 1. If an offer with Fixed Pricing type, but called takeOfferDynamic() function.
 * 2. If an offer with Dynamic Pricing type, but called takeOfferFixed() function.
 */
error IncorrectOfferPricingType(OfferPricingType incorrectOfferPricingType);

/**
 * @title Open Dotc smart contract (as part of the "SwarmX.eth Protocol")
 * @notice This contract handles decentralized over-the-counter trading.
 * @dev It uses ERC20, ERC721 and ERC1155 token standards for asset management and trade settlement.
 * ////////////////DISCLAIMER////////////////DISCLAIMER////////////////DISCLAIMER////////////////
 * Please read the Disclaimer featured on the SwarmX.eth website ("Terms") carefully before accessing,
 * interacting with, or using the SwarmX.eth Protocol software, consisting of the SwarmX.eth Protocol
 * technology stack (in particular its smart contracts) as well as any other SwarmX.eth technology such
 * as e.g., the launch kit for frontend operators (together the "SwarmX.eth Protocol Software").
 * By using any part of the SwarmX.eth Protocol you agree (1) to the Terms and acknowledge that you are
 * aware of the existing risk and knowingly accept it, (2) that you have read, understood and accept the
 * legal information and terms of service and privacy note presented in the Terms, and (3) that you are
 * neither a US person nor a person subject to international sanctions (in particular as imposed by the
 * European Union, Switzerland, the United Nations, as well as the USA). If you do not meet these
 * requirements, please refrain from using the SwarmX.eth Protocol.
 * ////////////////DISCLAIMER////////////////DISCLAIMER////////////////DISCLAIMER////////////////
 * @author Swarm
 */




contract DotcV2 is Initializable, Receiver {
    /// @dev Used for Safe transfer tokens.
    using SafeTransferLib for address;
    /// @dev Used for precise calculations.
    using FixedPointMathLib for uint256;
    /// @dev Used for Asset interaction.
    using AssetHelper for Asset;
    /// @dev Used for Offer interaction.
    using OfferHelper for OfferStruct;
    /// @dev Used for Dotc Offer interaction.
    using DotcOfferHelper for DotcOffer;

    /**
     * @notice Emitted when a new trading offer is created.
     * @param maker Address of the user creating the offer.
     * @param offerId Unique identifier of the created offer.
     * @param dotcOffer The details of the created offer.
     */
    event CreatedOffer(address indexed maker, uint256 indexed offerId, DotcOffer dotcOffer);

    /**
     * @notice Emitted when an offer is successfully taken.
     * @param offerId Unique identifier of the taken offer.
     * @param taker Address of the user taking the offer.
     * @param offerFillType Indicates if the offer is fully taken.
     * @param depositAssetAmount The amount of the deposit asset involved in the offer.
     * @param withdrawalAssetAmount The amount of the withdrawal asset involved in the offer.
     * @param affiliate Address of the affiliate involved in the trade.
     */
    event TakenOffer(
        uint256 indexed offerId,
        address indexed taker,
        OfferFillType indexed offerFillType,
        uint256 depositAssetAmount,
        uint256 withdrawalAssetAmount,
        address affiliate
    );

    /**
     * @notice Emitted when an offer is canceled.
     * @param offerId Unique identifier of the canceled offer.
     * @param depositAssetAmountMakerReceived The amount of the deposit asset returned to the maker.
     */
    event CanceledOffer(uint256 indexed offerId, uint256 depositAssetAmountMakerReceived);

    /**
     * @notice Emitted when the expiry time of an offer is updated.
     * @param offerId Unique identifier of the offer with updated expiry.
     * @param newExpiryTimestamp The new expiry timestamp of the offer.
     */
    event UpdatedOfferExpiry(uint256 indexed offerId, uint256 newExpiryTimestamp);

    /**
     * @notice Emitted when the timelock period of an offer is updated.
     * @param offerId Unique identifier of the offer with updated timelock.
     * @param newTimelockPeriod The new timelock period of the offer.
     */
    event UpdatedTimeLockPeriod(uint256 indexed offerId, uint256 newTimelockPeriod);

    /**
     * @notice Emitted when the terms and communication links for an offer are updated.
     * @param offerId Unique identifier of the offer with updated links.
     * @param newTerms The new terms for the offer.
     * @param newCommsLink The new communication link for the offer.
     */
    event OfferLinksUpdated(uint256 indexed offerId, string newTerms, string newCommsLink);

    /**
     * @notice Emitted when the array of special addresses of an offer is updated.
     * @param offerId Unique identifier of the offer with updated special addresses.
     * @param specialAddresses The new special addresses of the offer.
     */
    event OfferSpecialAddressesUpdated(uint256 indexed offerId, address[] specialAddresses);

    /**
     * @notice Emitted when the array of authorization addresses of an offer is updated.
     * @param offerId Unique identifier of the offer with updated authorization addresses.
     * @param authAddresses The new authorization addresses of the offer.
     */
    event OfferAuthAddressesUpdated(uint256 indexed offerId, address[] authAddresses);

    /**
     * @dev Address of the manager contract.
     */
    DotcManagerV2 public manager;
    /**
     * @dev Address of the escrow contract.
     */
    DotcEscrowV2 public escrow;

    /**
     * @notice Stores all the offers ever created.
     * @dev Maps an offer ID to its corresponding DotcOffer structure.
     */
    mapping(uint256 => DotcOffer) public allOffers;
    /**
     * @notice Keeps track of all offers created by a specific address.
     * @dev Maps an address to an array of offer IDs created by that address.
     */
    mapping(address => uint256[]) public offersFromAddress;
    /**
     * @notice Tracks the ID to be assigned to the next created offer.
     * @dev Incremented with each new offer, ensuring unique IDs for all offers.
     */
    uint256 public currentOfferId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with a given manager.
     * @param _manager The address of the manager to be set for this contract.
     */
    function initialize(DotcManagerV2 _manager) public initializer {
        manager = _manager;
    }

    /**
     * @notice Creates a new trading offer with specified assets and conditions.
     * @param depositAsset The asset to be deposited by the maker.
     * @param withdrawalAsset The asset desired by the maker in exchange.
     * @param offer The offer structure containing the offer details.
     * @dev Validates asset structure and initializes a new offer.
     */
    function makeOffer(
        Asset calldata depositAsset,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer
    ) external {
        depositAsset.checkAssetStructure(offer.offerPrice.offerPricingType);
        withdrawalAsset.checkAssetStructure(offer.offerPrice.offerPricingType);

        depositAsset.checkAssetOwner(msg.sender, depositAsset.amount);

        // offer.checkOfferStructure(depositAsset, withdrawalAsset);

        uint256 _currentOfferId = currentOfferId;

        DotcOffer memory dotcOffer = offer.buildOffer(depositAsset, withdrawalAsset);

        currentOfferId++;
        offersFromAddress[msg.sender].push(_currentOfferId);
        allOffers[_currentOfferId] = dotcOffer;

        // Sending DepositAsset from Maker to Escrow
        _assetTransfer(depositAsset, msg.sender, address(escrow), depositAsset.amount);

        escrow.setDeposit(_currentOfferId, msg.sender, depositAsset);

        emit CreatedOffer(msg.sender, _currentOfferId, dotcOffer);
    }

    /**
     * @notice Takes a fixed price offer.
     * @param offerId The ID of the offer to take.
     * @param withdrawalAmountPaid The amount paid to withdraw the asset.
     * @param affiliate The address of the affiliate.
     */
    function takeOfferFixed(uint256 offerId, uint256 withdrawalAmountPaid, address affiliate) external {
        DotcOffer memory offer = allOffers[offerId];
        offer.checkDotcOfferParams();
        // offer.offer.checkOfferParams();

        if (offer.offer.offerPrice.offerPricingType != OfferPricingType.FixedPricing) {
            revert IncorrectOfferPricingType(offer.offer.offerPrice.offerPricingType);
        }

        if (withdrawalAmountPaid == 0 || withdrawalAmountPaid > offer.withdrawalAsset.amount) {
            withdrawalAmountPaid = offer.withdrawalAsset.amount;
        }

        if (
            withdrawalAmountPaid != offer.withdrawalAsset.amount &&
            offer.offer.takingOfferType == TakingOfferType.BlockOffer
        ) {
            revert BlockOfferShouldBePaidFully(withdrawalAmountPaid);
        }

        offer.withdrawalAsset.checkAssetOwner(msg.sender, withdrawalAmountPaid);

        uint256 withdrawalAssetAmount = withdrawalAmountPaid;

        uint256 depositAssetAmount = withdrawalAmountPaid != offer.withdrawalAsset.amount
            ? offer.depositAsset.unstandardize(
                (
                    offer.withdrawalAsset.standardize(withdrawalAmountPaid).fullMulDiv(
                        AssetHelper.BPS,
                        offer.offer.offerPrice.unitPrice
                    )
                )
            )
            : offer.depositAsset.amount;

        allOffers[offerId].withdrawalAsset.amount -= withdrawalAmountPaid;
        allOffers[offerId].depositAsset.amount -= depositAssetAmount;

        OfferFillType offerFillType = (allOffers[offerId].withdrawalAsset.amount == 0 ||
            allOffers[offerId].depositAsset.amount == 0)
            ? OfferFillType.FullyTaken
            : OfferFillType.PartiallyTaken;

        allOffers[offerId].offerFillType = offerFillType;

        if (offer.withdrawalAsset.assetType == AssetType.ERC20) {
            // If WithdrawalAsset is an ERC20 then fees will be taken from Taker
            withdrawalAmountPaid -= _sendWithdrawalFees(offer.withdrawalAsset, withdrawalAmountPaid, affiliate);
        } else if (offer.depositAsset.assetType == AssetType.ERC20) {
            // If WithdrawalAsset is not an ERC20 then fees will be taken from Maker
            depositAssetAmount -= _sendDepositFees(offerId, depositAssetAmount, affiliate);
        }

        //Transfer WithdrawalAsset from Taker to Maker
        _assetTransfer(offer.withdrawalAsset, msg.sender, offer.maker, withdrawalAmountPaid);

        //Transfer DepositAsset from Maker to Taker
        escrow.withdrawDeposit(offerId, depositAssetAmount, msg.sender);

        emit TakenOffer(offerId, msg.sender, offerFillType, depositAssetAmount, withdrawalAssetAmount, affiliate);
    }

    /**
     * @notice Takes a dynamic price offer.
     * @param offerId The ID of the offer to take.
     * @param withdrawalAmountPaid The amount paid to withdraw the asset.
     * @param maximumDepositToWithdrawalRate The maximum deposit-to-withdrawal rate, should be in withdrawal Asset decimals
     * @param affiliate The address of the affiliate.
     */
    function takeOfferDynamic(
        uint256 offerId,
        uint256 withdrawalAmountPaid,
        uint256 maximumDepositToWithdrawalRate,
        address affiliate
    ) external {
        DotcOffer memory offer = allOffers[offerId];
        offer.checkDotcOfferParams();
        offer.offer.checkOfferParams();

        if (offer.offer.offerPrice.offerPricingType != OfferPricingType.DynamicPricing) {
            revert IncorrectOfferPricingType(offer.offer.offerPrice.offerPricingType);
        }

        (uint256 depositToWithdrawalRate, uint256 withdrawalPrice) = offer.depositAsset.getRateAndPrice(
            offer.withdrawalAsset,
            offer.offer.offerPrice
        );

        if (maximumDepositToWithdrawalRate == 0) {
            maximumDepositToWithdrawalRate = depositToWithdrawalRate;
        }

        if (depositToWithdrawalRate > maximumDepositToWithdrawalRate) {
            revert DepositToWithdrawalRateOverflow();
        }

        if (withdrawalAmountPaid == 0 || withdrawalAmountPaid > withdrawalPrice) {
            withdrawalAmountPaid = withdrawalPrice;
        }

        if (
            withdrawalAmountPaid != offer.withdrawalAsset.amount &&
            offer.offer.takingOfferType == TakingOfferType.BlockOffer
        ) {
            revert BlockOfferShouldBePaidFully(withdrawalAmountPaid);
        }

        uint256 fullWithdrawalAmountPaid = withdrawalAmountPaid;

        offer.withdrawalAsset.checkAssetOwner(msg.sender, withdrawalAmountPaid);

        uint256 depositAssetAmount;
        if (offer.depositAsset.assetType != AssetType.ERC20) {
            depositAssetAmount = withdrawalAmountPaid.fullMulDiv(offer.depositAsset.amount, withdrawalPrice);
        } else {
            depositAssetAmount = AssetHelper.calculatePercentage(
                offer.depositAsset.amount,
                AssetHelper.getPartPercentage(withdrawalAmountPaid, withdrawalPrice)
            );
        }
        uint256 fullDepositAssetAmount = depositAssetAmount;

        allOffers[offerId].depositAsset.amount -= depositAssetAmount;
        allOffers[offerId].withdrawalAsset.amount = withdrawalPrice - withdrawalAmountPaid;

        OfferFillType offerFillType = allOffers[offerId].depositAsset.amount == 0 ||
            allOffers[offerId].withdrawalAsset.amount == 0
            ? OfferFillType.FullyTaken
            : OfferFillType.PartiallyTaken;

        allOffers[offerId].offerFillType = offerFillType;

        if (offer.withdrawalAsset.assetType == AssetType.ERC20) {
            // If WithdrawalAsset is an ERC20 then fees will be taken from Taker
            withdrawalAmountPaid -= _sendWithdrawalFees(offer.withdrawalAsset, withdrawalAmountPaid, affiliate);
        } else if (offer.depositAsset.assetType == AssetType.ERC20) {
            // If WithdrawalAsset is not an ERC20 then fees will be taken from Maker
            depositAssetAmount -= _sendDepositFees(offerId, depositAssetAmount, affiliate);
        }

        //Transfer WithdrawalAsset from Taker to Maker
        _assetTransfer(offer.withdrawalAsset, msg.sender, offer.maker, withdrawalAmountPaid);

        //Transfer DepositAsset from Maker to Taker
        escrow.withdrawDeposit(offerId, depositAssetAmount, msg.sender);

        emit TakenOffer(
            offerId,
            msg.sender,
            offerFillType,
            fullDepositAssetAmount,
            fullWithdrawalAmountPaid,
            affiliate
        );
    }

    /**
     * @notice Updates an existing offer's details.
     * @param offerId The ID of the offer to update.
     * @param updatedOffer A structure for the updated offer.
     * @dev Only the maker of the offer can update it.
     */
    function updateOffer(uint256 offerId, OfferStruct calldata updatedOffer) external {
        DotcOffer memory offer = allOffers[offerId];

        offer.onlyMaker();
        offer.checkDotcOfferParams();

        if (updatedOffer.specialAddresses.length > 0) {
            OfferHelper.checkAddressesArrayForZeroAddresses(updatedOffer.specialAddresses);

            allOffers[offerId].offer.specialAddresses = updatedOffer.specialAddresses;
            emit OfferSpecialAddressesUpdated(offerId, updatedOffer.specialAddresses);
        }

        if (updatedOffer.authorizationAddresses.length > 0) {
            OfferHelper.checkAddressesArrayForZeroAddresses(updatedOffer.authorizationAddresses);

            allOffers[offerId].offer.authorizationAddresses = updatedOffer.authorizationAddresses;
            emit OfferAuthAddressesUpdated(offerId, updatedOffer.authorizationAddresses);
        }

        if (updatedOffer.expiryTimestamp > offer.offer.expiryTimestamp) {
            allOffers[offerId].offer.expiryTimestamp = updatedOffer.expiryTimestamp;
            emit UpdatedOfferExpiry(offerId, updatedOffer.expiryTimestamp);
        }

        if (
            updatedOffer.timelockPeriod > offer.offer.timelockPeriod &&
            allOffers[offerId].offer.expiryTimestamp > updatedOffer.timelockPeriod
        ) {
            allOffers[offerId].offer.timelockPeriod = updatedOffer.timelockPeriod;
            emit UpdatedTimeLockPeriod(offerId, updatedOffer.timelockPeriod);
        }

        if (
            keccak256(abi.encodePacked(updatedOffer.terms)) != keccak256("") &&
            keccak256(abi.encodePacked(updatedOffer.commsLink)) != keccak256("")
        ) {
            allOffers[offerId].offer.terms = updatedOffer.terms;
            allOffers[offerId].offer.commsLink = updatedOffer.commsLink;
            emit OfferLinksUpdated(offerId, updatedOffer.terms, updatedOffer.commsLink);
        }
    }

    /**
     * @notice Cancels an offer and refunds the maker.
     * @param offerId The ID of the offer to cancel.
     * @dev Can only be called by the offer's maker and when the timelock has passed.
     */
    function cancelOffer(uint256 offerId) external {
        DotcOffer memory offer = allOffers[offerId];

        offer.onlyMaker();
        offer.checkDotcOfferParams();

        allOffers[offerId].offerFillType = OfferFillType.Cancelled;

        uint256 amountToWithdraw = escrow.cancelDeposit(offerId, msg.sender);

        emit CanceledOffer(offerId, amountToWithdraw);
    }

    /**
     * @notice Changes the escrow address.
     * @param _escrow The new escrow's address.
     * @dev Ensures that only the current owner can perform this operation.
     */
    function changeEscrow(DotcEscrowV2 _escrow) external {
        if (msg.sender != address(manager)) {
            revert OnlyManager();
        }

        escrow = _escrow;
    }

    /**
     * @dev Internal function to handle the transfer of different types of assets (ERC20, ERC721, ERC1155).
     * @param asset The asset to be transferred.
     * @param from The address sending the asset.
     * @param to The address receiving the asset.
     * @param amount The amount of the asset to transfer.
     */
    function _assetTransfer(Asset memory asset, address from, address to, uint256 amount) private {
        if (asset.assetType == AssetType.ERC20) {
            asset.assetAddress.safeTransferFrom(from, to, amount);
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.assetAddress).safeTransferFrom(from, to, asset.tokenId);
        } else if (asset.assetType == AssetType.ERC1155) {
            IERC1155(asset.assetAddress).safeTransferFrom(from, to, asset.tokenId, asset.amount, "");
        }
    }

    /**
     * @dev Internal function to handle the sending of withdrawal fees.
     * @param asset The asset from which the fees will be sent.
     * @param assetAmount The amount of the asset.
     * @param affiliate The address of the affiliate.
     * @return The fees amount.
     */
    function _sendWithdrawalFees(Asset memory asset, uint256 assetAmount, address affiliate) private returns (uint256) {
        (uint256 fees, uint256 feesToFeeReceiver, uint256 feesToAffiliate, address feeReceiver) = _validateFees(
            assetAmount
        );

        if (fees == 0) {
            return 0;
        }

        if (affiliate != address(0)) {
            _assetTransfer(asset, msg.sender, feeReceiver, feesToFeeReceiver);
            _assetTransfer(asset, msg.sender, affiliate, feesToAffiliate);
        } else {
            _assetTransfer(asset, msg.sender, feeReceiver, fees);
        }

        return fees;
    }

    /**
     * @dev Internal function to handle the sending of deposit fees.
     * @param offerId The ID of the offer.
     * @param assetAmount The amount of the asset.
     * @param affiliate The address of the affiliate.
     * @return The fees amount.
     */
    function _sendDepositFees(uint256 offerId, uint256 assetAmount, address affiliate) private returns (uint256) {
        (uint256 fees, uint256 feesToFeeReceiver, uint256 feesToAffiliate, ) = _validateFees(assetAmount);

        if (fees == 0) {
            return 0;
        }

        if (affiliate != address(0)) {
            escrow.withdrawFees(offerId, feesToFeeReceiver);
            escrow.withdrawFees(offerId, feesToAffiliate, affiliate);
        } else {
            escrow.withdrawFees(offerId, fees);
        }

        return fees;
    }

    function _validateFees(
        uint256 assetAmount
    ) private view returns (uint256 fees, uint256 feesToFeeReceiver, uint256 feesToAffiliate, address feeReceiver) {
        uint256 feeAmount = manager.feeAmount();
        feeReceiver = manager.feeReceiver();

        if (feeAmount == 0 || feeReceiver == address(0)) {
            return (0, 0, 0, address(0));
        }

        (fees, feesToFeeReceiver, feesToAffiliate) = AssetHelper.getFees(
            assetAmount,
            feeAmount,
            manager.revSharePercentage()
        );
    }
}