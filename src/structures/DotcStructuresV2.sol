// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

/// @title Errors related to offer management in the Dotc Structures.
/// @notice Provides error messages for various failure conditions related to dotc structures handling.

/**
 * @notice Indicates that the operation was attempted by a non owner address.
 */
error OnlyManager();

/**
 * @notice Indicates that the operation was attempted by an unauthorized entity, not the Dotc contract.
 */
error OnlyDotc();

/**
 * @notice Indicates usage of a zero address where an actual address is required.
 */
error ZeroAddressPassed();

/**
 * @notice Indicates that an incorrect percentage amount was passed.
 * @param incorrectRevShare The incorrect percentage amount that was passed.
 */
error IncorrectPercentage(uint256 incorrectRevShare);

/**
 * @title Structures for DOTC management (as part of the "SwarmX.eth Protocol")
 * @notice Contains structures and enumerations for managing offers in the SwarmX.eth Protocol.
 * @author Swarm
 * @dev This contract includes multiple enumerations and structures used for managing offers within the DOTC system.
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
 */

/**
 * @title Asset Types Enum.
 * @notice Defines the different types of assets that can be used in the system.
 * @dev Enum representing various asset types supported in DOTC trades.
 * @author Swarm
 * - NoType: Represents a state with no specific asset type.
 * - ERC20: Represents an ERC20 token asset.
 * - ERC721: Represents an ERC721 token (NFT) asset.
 * - ERC1155: Represents an ERC1155 token (multi-token standard) asset.
 */
enum AssetType {
    NoType,
    ERC20,
    ERC721,
    ERC1155
}

/**
 * @title Offer Pricing Types Enum.
 * @notice Defines the different types of pricing offers that can be used in the system.
 * @dev Enum representing various pricing offer types supported in DOTC trades.
 * @author Swarm
 * - NoType: Represents a state with no specific offer type.
 * - FixedPricing: Represents a Fixed Pricing offer type where `maker` specifies a fixed price.
 * - DynamicPricing: Represents a Dynamic Pricing offer type where `maker` specifies price feeds for assets.
 */
enum OfferPricingType {
    NoType,
    FixedPricing,
    DynamicPricing
}

/**
 * @title Offer Types Enum.
 * @notice Defines the different types of taking offers that can be used in the system.
 * @dev Enum representing various taking offer types supported in DOTC trades.
 * @author Swarm
 * - NoType: Represents a state with no specific taking offer type.
 * - PartialOffer: Represents a Partial Taking offer type where `taker` can take not the full amount of assets.
 * - BlockOffer: Represents a Fully Taking offer type where `taker` should take the full amount of assets.
 */
enum TakingOfferType {
    NoType,
    PartialOffer,
    BlockOffer
}

/**
 * @title Percentage Types Enum.
 * @notice Defines the different types of percentage calculation that can be used in the system.
 * @dev Enum representing various percentage types supported in DOTC trades.
 * @author Swarm
 * - NoType: Represents a state with no specific percentage type.
 * - Plus: Represents an action of adding a percentage to a value.
 * - Minus: Represents an action of subtracting a percentage from a value.
 */
enum PercentageType {
    NoType,
    Plus,
    Minus
}

/**
 * @title Offer Fill Type Enum.
 * @notice Defines the types of validity states an offer can have in the DOTC system.
 * @dev Enum representing different states of offer validity, like non-existent or fully taken.
 * - NotTaken: The offer has not been taken.
 * - Cancelled: The offer has been cancelled.
 * - PartiallyTaken: The offer has been partially taken.
 * - FullyTaken: The offer has been fully taken.
 * @author Swarm
 */
enum OfferFillType {
    NotTaken,
    Cancelled,
    PartiallyTaken,
    FullyTaken
}

/**
 * @title Escrow Offer Status Type Enum.
 * @notice Defines the types of escrow states an offer can have in the DOTC system.
 * @dev Enum representing different states of escrow, like offer deposited or fully withdrew.
 * @author Swarm
 * - NoType: Represents a state with no specific escrow type.
 * - OfferDeposited: Indicates that the offer has been deposited.
 * - OfferFullyWithdrawn: Indicates that the offer has been fully withdrawn.
 * - OfferPartiallyWithdrawn: Indicates that the offer has been partially withdrawn.
 * - OfferCancelled: Indicates that the offer has been cancelled.
 */
enum EscrowOfferStatusType {
    NoType,
    OfferDeposited,
    OfferFullyWithdrawn,
    OfferPartiallyWithdrawn,
    OfferCancelled
}

/**
 * @title Asset Price Structure.
 * @notice Represents the price details in the DOTC trading system.
 * @dev Defines the structure for price details including price feed address, offerMaximumPrice, offerMinimumPrice, and percentage.
 * @author Swarm
 * @param priceFeedAddress The contract address of the price feed for this asset.
 * @param offerMaximumPrice The maximum price limit.
 * @param offerMinimumPrice The minimum price limit.
 */
struct AssetPrice {
    address priceFeedAddress;
    uint256 offerMaximumPrice;
    uint256 offerMinimumPrice;
}

/**
 * @title Offer Price Structure.
 * @notice Represents the pricing details of an offer in the DOTC trading system.
 * @dev Defines the structure for offer pricing details including pricing type, unit price, percentage, and percentage type.
 * @author Swarm
 * @param offerPricingType The type of the offer pricing (FixedPricing, DynamicPricing).
 * @param unitPrice The unit price of the offer.
 * @param percentage The percentage to be applied to the unit price.
 * @param percentageType The type of percentage calculation (Plus, Minus).
 */
struct OfferPrice {
    OfferPricingType offerPricingType;
    uint256 unitPrice;
    uint256 percentage;
    PercentageType percentageType;
}

/**
 * @title Asset Structure.
 * @notice Represents an asset in the DOTC trading system.
 * @dev Defines the structure for an asset including type, address, amount, and token ID for NFTs.
 * @author Swarm
 * @param assetType The type of the asset (ERC20, ERC721, ERC1155).
 * @param assetAddress The contract address of the asset.
 * @param amount The amount of the asset (relevant for ERC20 and ERC1155).
 * @param tokenId The token ID (relevant for ERC721 and ERC1155).
 * @param assetPrice The price details of the asset.
 */
struct Asset {
    AssetType assetType;
    address assetAddress;
    uint256 amount;
    uint256 tokenId;
    AssetPrice assetPrice;
}

/**
 * @title Offer Structure for DOTC.
 * @notice Describes the structure of an offer within the DOTC trading system.
 * @dev Structure encapsulating details of an offer, including its type, special conditions, and timing constraints.
 * @author Swarm
 * @param takingOfferType The type of the offer taking (Partial, Fully).
 * @param offerPricingType The type of the offer pricing (FixedPricing, DynamicPricing).
 * @param specialAddresses Array of addresses with exclusive rights to take the offer.
 * @param authorizationAddresses Array of addresses authorized to take the offer.
 * @param expiryTimestamp Unix timestamp marking the offer's expiration.
 * @param timelockPeriod Duration in seconds for which the offer is locked from being taken.
 * @param terms String URL pointing to the terms associated with the offer.
 * @param commsLink String URL providing a communication link (e.g., Telegram, email) for discussing the offer.
 */
struct OfferStruct {
    TakingOfferType takingOfferType;
    OfferPrice offerPrice;
    address[] specialAddresses;
    address[] authorizationAddresses;
    uint256 expiryTimestamp;
    uint256 timelockPeriod;
    string terms;
    string commsLink;
}

/**
 * @title DOTC Offer Structure.
 * @notice Detailed structure of an offer in the DOTC trading system.
 * @dev Contains comprehensive information about an offer, including assets involved and trade conditions.
 * @author Swarm
 * @param maker Address of the individual creating the offer.
 * @param offerFillType The type of the dotc offer validation (NotExist, PartiallyTaken, FullyTaken).
 * @param depositAsset Asset offered by the maker.
 * @param withdrawalAsset Asset requested by the maker in exchange.
 * @param offer Detailed structure of the offer including special conditions and timing.
 */
struct DotcOffer {
    address maker;
    OfferFillType offerFillType;
    Asset depositAsset;
    Asset withdrawalAsset;
    OfferStruct offer;
}

/**
 * @title Escrow Offer Structure.
 * @notice Represents the escrow details of an offer in the DOTC trading system.
 * @dev Defines the structure for escrow details including escrow type and deposit asset.
 * @author Swarm
 * @param escrowOfferStatusType The type of the escrow (OfferDeposited, OfferFullyWithdrawn, etc.).
 * @param depositAsset The asset being deposited in the escrow.
 */
struct EscrowDeposit {
    EscrowOfferStatusType escrowOfferStatusType;
    Asset depositAsset;
}