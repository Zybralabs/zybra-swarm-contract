// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { Asset, AssetType, OfferFillType, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType } from "../src/structures/DotcStructuresV2.sol";
import "./BaseTest.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract depositTest is BaseTest {
    uint256 AMOUNT = 100e18;
    // Mock withdrawal asset and offer
    Asset withdrawalAsset;
    Asset withdrawalAsset2;
    Asset withdrawalAsset2;
    OfferStruct offer;
    OfferStruct offer2;
    OfferStruct offer3;
    uint256 offerId;
    // --- Events ---
    event depositAsset(address indexed user, address indexed asset, uint256 amount);

       function setUp() public {
        // Mint initial balances for USDC
        USDC.mint(self, initialBalance);  // Mint for test contract
        USDC.mint(investor, initialBalance);  // Optional investor balance

        // User approves the lzybravault to spend their USDC
        vm.startPrank(user);
        USDC.approve(address(lzybravault), initialBalance);
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

        OfferStruct offer = OfferStruct({
        takingOfferType: TakingOfferType.BlockOffer, // Example enum value (2) for BlockOffer
        offerPrice: OfferPrice({
        offerPricingType: OfferPricingType.FixedPricing, // Pricing type (FixedPricing)
        unitPrice: 10e18, // Setting the unit price to 0 in this example
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

  OfferStruct offer2 = OfferStruct({
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

  OfferStruct offer3 = OfferStruct({
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

        dotcV2.makeOffer(depositAsset, withdrawalAsset, offer);

    }

    function testdepositAndMintWithReverts() public {
        // Prank user for deposit
        vm.startPrank(user);
        offerId++;
        // --- 1. Test deposit and Mint ---
        lzybravault.deposit(assetAmount, withdrawalAsset, offerId);

        // Assert user balance after deposit
        assertEq(USDC.balanceOf(user), initialBalance - assetAmount, "User USDC balance not reduced correctly");

        // Assert correct LZYBRA minting
        uint256 expectedMintAmount = assetAmount * fakeOfferPrice;
        assertEq(lzybra.balanceOf(user), expectedMintAmount, "LZYBRA tokens minted incorrectly");

 

        // --- 2. Test Multiple deposits ---
        lzybravault.deposit(assetAmount, withdrawalAsset, offer);
        assertEq(USDC.balanceOf(user), initialBalance - (2 * assetAmount), "Second deposit failed");

        // Verify cumulative LZYBRA minting
        uint256 totalMintAmount = 2 * (assetAmount * fakeOfferPrice);
        assertEq(lzybra.balanceOf(user), totalMintAmount, "Incorrect LZYBRA mint amount after multiple deposits");

        // --- 3. Test Zero deposit ---
        vm.expectRevert("deposit amount must be greater than 0");
        lzybravault.deposit(0, withdrawalAsset, offer);

        vm.stopPrank();
    }

    function testdepositWithInvalidConditions() public {
        // --- 1. Test Invalid Offer Price ---
        offer.offerPrice = OfferPrice({ unitPrice: 0 });

        // Prank user trying to deposit with invalid offer
        vm.startPrank(user);
        vm.expectRevert("Invalid offer price");
        lzybravault.deposit(assetAmount, withdrawalAsset, offer);

        // --- 2. Test deposit Without Approval ---
        USDC.approve(address(lzybravault), 0);  // Revoke approval
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        lzybravault.deposit(assetAmount, withdrawalAsset, offer);

        // --- 3. Test DOTCV2 Offer Call ---
        USDC.approve(address(lzybravault), initialBalance); // Re-approve for valid test
        vm.expectCall(address(dotcV2), abi.encodeWithSelector(dotcV2.makeOffer.selector, withdrawalAsset, withdrawalAsset, offer));
        lzybravault.deposit(assetAmount, withdrawalAsset, offer);

        vm.stopPrank();
    }
}
