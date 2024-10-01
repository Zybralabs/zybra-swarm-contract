// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { Asset, AssetType, OfferFillType,PercentageType,OfferPrice ,OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType } from "../src/structures/DotcStructuresV2.sol";
import "./BaseTest.sol";

contract depositTest is BaseTest {
    uint256 AMOUNT = 100e18;
    // Mock withdrawal asset and offer
    Asset asset;
    Asset asset2;
    Asset asset3;
    OfferStruct offer;
    OfferStruct offer2;
    OfferStruct offer3;
    uint256 offerId;
    // --- Events ---
    event depositAsset(address indexed user, address indexed asset, uint256 amount);

       function setUp() public {
        // Mint initial balances for USDC
        USDC.mint(self, AMOUNT);  // Mint for test contract
        USDC.mint(investor, AMOUNT);  // Optional investor balance

        // User approves the lzybravault to spend their USDC
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        asset.approve(address(lzybravault), AMOUNT);
        asset2.approve(address(lzybravault), AMOUNT);
        asset3.approve(address(lzybravault), AMOUNT);
        vm.stopPrank();

         asset1.requestMint(AMOUNT);
         asset1.requestMint(AMOUNT,investor);
         asset1.requestMint(AMOUNT,user);

         asset2.requestMint(AMOUNT);
         asset2.requestMint(AMOUNT,investor);
         asset2.requestMint(AMOUNT,user);

         asset3.requestMint(AMOUNT);
         asset3.requestMint(AMOUNT,investor);
         asset3.requestMint(AMOUNT,user);
  

        // Set up withdrawal asset for the offer
   Asset depositAsset = Asset({
    assetType: 0, // Assuming assetType 0 represents some standard like ERC20
    assetAddress: address(USDC), // Example deposit asset address
    amount: defaultPrice, // Example deposit amount
    tokenId: 0, // No specific tokenId for this asset (since it's not an NFT)
    assetPrice: (address(ChainLinkMockUSDC), 0, 0) // Example price feed tuple
});

    Asset withdrawalAsset1 = Asset({
    assetType: 1, // Assuming assetType 1 represents ERC20 or another type
    assetAddress: address(asset1), // Example withdrawal asset address
    amount: defaultPrice * 10, // Example withdrawal amount
    tokenId: 0, // No tokenId for the withdrawal asset
    assetPrice: (address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
});

   Asset withdrawalAsset2 = Asset({
    assetType: 1, // Assuming assetType 1 represents ERC20 or another type
    assetAddress: address(asset1), // Example withdrawal asset address
    amount: defaultPrice * 10, // Example withdrawal amount
    tokenId: 0, // No tokenId for the withdrawal asset
    assetPrice: (address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
});

   Asset withdrawalAsset3 = Asset({
    assetType: 1, // Assuming assetType 1 represents ERC20 or another type
    assetAddress: address(asset1), // Example withdrawal asset address
    amount: defaultPrice * 10, // Example withdrawal amount
    tokenId: 0, // No tokenId for the withdrawal asset
    assetPrice: (address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
});

         offer = OfferStruct({
        takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
        offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 10e18, // Setting the unit price to 0 in this example
        percentage: 0, // No percentage used
        percentageType: PercentageType.NoType // No percentage type used
        }),
        specialAddresses: "",
        authorizationAddresses: [address(this),user,investor] , 
        expiryTimestamp: block.timestamp + 2 days, // Example expiry timestamp
        timelockPeriod: 0, // No timelock period
        terms: "tbd", // Placeholder for offer terms
        commsLink: "tbd" // Placeholder for communication link
});

   offer2 = OfferStruct({
        takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
        offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 5e18, // Setting the unit price to 0 in this example
        percentage: 0, // No percentage used
        percentageType: PercentageType.NoType // No percentage type used
        }),
        specialAddresses: "",
        authorizationAddresses: [user,investor] , 
        expiryTimestamp: block.timestamp + 2 days, // Example expiry timestamp
        timelockPeriod: 0, // No timelock period
        terms: "tbd", // Placeholder for offer terms
        commsLink: "tbd" // Placeholder for communication link
});

   offer3 = OfferStruct({
        takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
        offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 15e18, // Setting the unit price to 0 in this example
        percentage: 0, // No percentage used
        percentageType: PercentageType.NoType // No percentage type used
        }),
        specialAddresses: "",
        authorizationAddresses: [user,investor] , 
        expiryTimestamp: block.timestamp + 2 days, // Example expiry timestamp
        timelockPeriod: 0, // No timelock period
        terms: "tbd", // Placeholder for offer terms
        commsLink: "tbd" // Placeholder for communication link
});

        dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer);
        dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);
        dotcV2.makeOffer(depositAsset, withdrawalAsset3, offer3);


        uint256 amount = 2 *10**18;
        vm.startPrank(user);
        lzybravault.deposit(amount, withdrawalAsset1, 1);
        lzybravault.deposit(amount, withdrawalAsset2, 2);

    }

  

 
}
