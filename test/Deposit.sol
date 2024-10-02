// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { Asset, AssetType,AssetPrice, OfferFillType,PercentageType,OfferPrice ,OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType } from "../src/structures/DotcStructuresV2.sol";
import "./BaseTest.sol";

contract depositTest is BaseTest {
    uint256 AMOUNT = 100e18;
    // Mock withdrawal asset and offer

    Asset withdrawalAsset1;
    Asset withdrawalAsset2;
    Asset withdrawalAsset3;
    Asset depositAsset;
    
    OfferStruct offer;
    OfferStruct offer2;
    OfferStruct offer3;
    uint256 offerId;
    // --- Events ---

       function deposit() public {
        // Mint initial balances for USDC
        USDC.mint(self, AMOUNT);  // Mint for test contract
        USDC.mint(investor, AMOUNT);  // Optional investor balance

        // User approves the lzybravault to spend their USDC
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        asset1.approve(address(lzybravault), AMOUNT);
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
    depositAsset = Asset({
    assetType: AssetType.ERC20, // Assuming assetType 0 represents some standard like ERC20
    assetAddress: address(USDC), // Example deposit asset address
    amount: defaultPrice, // Example deposit amount
    tokenId: 0, // No specific tokenId for this asset (since it's not an NFT)
    assetPrice: AssetPrice(address(ChainLinkMockUSDC), 0, 0) // Example price feed tuple
});

     withdrawalAsset1 = Asset({
    assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
    assetAddress: address(asset1), // Example withdrawal asset address
    amount: defaultPrice * 10, // Example withdrawal amount
    tokenId: 0, // No tokenId for the withdrawal asset
    assetPrice: AssetPrice(address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
});

    withdrawalAsset2 = Asset({
    assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
    assetAddress: address(asset1), // Example withdrawal asset address
    amount: defaultPrice * 10, // Example withdrawal amount
    tokenId: 0, // No tokenId for the withdrawal asset
    assetPrice: AssetPrice(address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
});

    withdrawalAsset3 = Asset({
    assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
    assetAddress: address(asset1), // Example withdrawal asset address
    amount: defaultPrice * 10, // Example withdrawal amount
    tokenId: 0, // No tokenId for the withdrawal asset
    assetPrice: AssetPrice(address(ChainLinkMockMSCRF), 0, 0) // Example price feed tuple
});
offer = OfferStruct({
    takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
    offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 10e18, // Setting the unit price to 10e18
        percentage: 0, // No percentage used
        percentageType: PercentageType.NoType // No percentage type used
    }),
    specialAddresses:  address()[1] , // Empty array for specialAddresses
    authorizationAddresses: address()[1] , // Array of 3 addresses
    expiryTimestamp: block.timestamp + 2 days, // Example expiry timestamp
    timelockPeriod: 0, // No timelock period
    terms: "tbd", // Placeholder for offer terms
    commsLink: "tbd" // Placeholder for communication link
});

// Set authorizationAddresses values for offer
offer.authorizationAddresses[0] = address(this);
offer.authorizationAddresses[1] = user;
offer.authorizationAddresses[2] = investor;


offer2 = OfferStruct({
    takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
    offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 5e18, // Setting the unit price to 5e18
        percentage: 0, // No percentage used
        percentageType: PercentageType.NoType // No percentage type used
    }),
    specialAddresses: [] , // Array for specialAddresses
    authorizationAddresses: [] , // Array of 2 addresses
    expiryTimestamp: block.timestamp + 2 days, // Example expiry timestamp
    timelockPeriod: 0, // No timelock period
    terms: "tbd", // Placeholder for offer terms
    commsLink: "tbd" // Placeholder for communication link
});

// Set values for offer2
offer2.specialAddresses[0] = address(this);
offer2.authorizationAddresses[0] = user;
offer2.authorizationAddresses[1] = investor;


offer3 = OfferStruct({
    takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
    offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 15e18, // Setting the unit price to 15e18
        percentage: 0, // No percentage used
        percentageType: PercentageType.NoType // No percentage type used
    }),
    specialAddresses:  address()[1] , // Array of 1 address
    authorizationAddresses:  address()[1] , // Array of 2 addresses
    expiryTimestamp: block.timestamp + 2 days, // Example expiry timestamp
    timelockPeriod: 0, // No timelock period
    terms: "tbd", // Placeholder for offer terms
    commsLink: "tbd" // Placeholder for communication link
});

// Set specialAddresses and authorizationAddresses for offer3
offer3.specialAddresses[0] = user;
offer3.authorizationAddresses[0] = user;
offer3.authorizationAddresses[1] = investor;


        dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer);
        dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);
        dotcV2.makeOffer(depositAsset, withdrawalAsset3, offer3);


        uint256 amount = 2 *10**18;
        vm.startPrank(user);
        lzybravault.deposit(amount, withdrawalAsset1, 1);
        lzybravault.deposit(amount, withdrawalAsset2, 2);

    }

  

 
}
