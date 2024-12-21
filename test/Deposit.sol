// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.19;

// import "forge-std/Test.sol";
// import {Asset, AssetType, AssetPrice, OfferFillType, PercentageType, OfferPrice, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType} from "../src/structures/DotcStructuresV2.sol";
// import "./BaseTest.sol";

// contract depositTest is BaseTest {
//     uint256 AMOUNT = 100e18;
//     // Mock withdrawal asset and offer

//     Asset withdrawalAsset1;
//     Asset withdrawalAsset2;
//     Asset withdrawalAsset3;
//     Asset depositAsset;

//     OfferStruct offer;
//     OfferStruct offer2;
//     OfferStruct offer3;
//     uint256 offerId;
//     // --- Events ---
//     // Initialize price feed IDs and data
//     bytes32 public id1;
//     bytes32 public id2;
//     bytes32 public id3;

//     int64 public price1 = 10e7;
//     int64 public price2 = 15e7;
//     int64 public price3 = 20e7;

//     uint64 public conf1 = 1e7;
//     uint64 public conf2 = 2e7;
//     uint64 public conf3 = 3e7;

//     int32 public expo1 = 0;
//     int32 public expo2 = 0;
//     int32 public expo3 = 0;

//     int64 public emaPrice1 = 10e7;
//     int64 public emaPrice2 = 15e7;
//     int64 public emaPrice3 = 20e7;

//     uint64 public emaConf1 = 1e7;
//     uint64 public emaConf2 = 2e7;
//     uint64 public emaConf3 = 3e7;

//     uint64 public publishTime1 = uint64(block.timestamp);
//     uint64 public publishTime2 = uint64(block.timestamp + 1 days);
//     uint64 public publishTime3 = uint64(block.timestamp + 2 days);

//     uint64 public prevPublishTime1 = uint64(block.timestamp - 1 days);
//     uint64 public prevPublishTime2 = uint64(block.timestamp);
//     uint64 public prevPublishTime3 = uint64(block.timestamp + 1 days);

//     function testDeposit() public {
//         // Mint initial balances for USDC
//         USDC.mint(self, AMOUNT); // Mint for test contract
//         USDC.mint(investor, AMOUNT); // Optional investor balance

//         // User approves the lzybravault to spend their USDC
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         asset1.approve(address(lzybravault), AMOUNT);
//         asset2.approve(address(lzybravault), AMOUNT);
//         asset3.approve(address(lzybravault), AMOUNT);
//         vm.stopPrank();

//         asset1.requestMint(AMOUNT);
//         asset1.requestMint(AMOUNT, investor);
//         asset1.requestMint(AMOUNT, user);

//         asset2.requestMint(AMOUNT);
//         asset2.requestMint(AMOUNT, investor);
//         asset2.requestMint(AMOUNT, user);

//         asset3.requestMint(AMOUNT);
//         asset3.requestMint(AMOUNT, investor);
//         asset3.requestMint(AMOUNT, user);

//         // Set up withdrawal asset for the offer
//         depositAsset = Asset({
//             assetType: AssetType.ERC20, // Assuming assetType 0 represents some standard like ERC20
//             assetAddress: address(USDC), // Example deposit asset address
//             amount: defaultPrice, // Example deposit amount
//             tokenId: 0, // No specific tokenId for this asset (since it's not an NFT)
//             assetPrice: AssetPrice(address(ChainLinkMockUSDC), 0, 0) // Example price feed tuple
//         });

//         withdrawalAsset1 = Asset({
//             assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
//             assetAddress: address(asset1), // Example withdrawal asset address
//             amount: defaultPrice * 3, // Example withdrawal amount
//             tokenId: 0, // No tokenId for the withdrawal asset
//             assetPrice: AssetPrice(address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
//         });

//         withdrawalAsset2 = Asset({
//             assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
//             assetAddress: address(asset2), // Example withdrawal asset address
//             amount: defaultPrice * 1, // Example withdrawal amount
//             tokenId: 0, // No tokenId for the withdrawal asset
//             assetPrice: AssetPrice(address(ChainLinkMockNVIDIA), 0, 0) // Example price feed tuple
//         });

//         withdrawalAsset3 = Asset({
//             assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
//             assetAddress: address(asset3), // Example withdrawal asset address
//             amount: defaultPrice * 3, // Example withdrawal amount
//             tokenId: 0, // No tokenId for the withdrawal asset
//             assetPrice: AssetPrice(address(ChainLinkMockMSCRF), 0, 0) // Example price feed tuple
//         });

//         // Fix: Dynamically initialize the array
//         offer = OfferStruct({
//             takingOfferType: TakingOfferType.BlockOffer,
//             offerPrice: OfferPrice({
//                 offerPricingType: OfferPricingType.FixedPricing,
//                 unitPrice: 10e18,
//                 percentage: 0,
//                 percentageType: PercentageType.NoType
//             }),
//             specialAddresses: specialAddress, // Initialize empty array with size 2
//             authorizationAddresses: authorizationAddresses, // Initialize empty array with size 3
//             expiryTimestamp: block.timestamp + 2 days,
//             timelockPeriod: 0,
//             terms: "tbd",
//             commsLink: "tbd"
//         });

//         // Repeat the process for the second offer

//         offer2 = OfferStruct({
//             takingOfferType: TakingOfferType.BlockOffer,
//             offerPrice: OfferPrice({
//                 offerPricingType: OfferPricingType.FixedPricing,
//                 unitPrice: 5e18,
//                 percentage: 0,
//                 percentageType: PercentageType.NoType
//             }),
//             specialAddresses: specialAddress, // Initialize array with 2 addresses
//             authorizationAddresses: authorizationAddresses, // Initialize array with 2 addresses
//             expiryTimestamp: block.timestamp + 2 days,
//             timelockPeriod: 0,
//             terms: "tbd",
//             commsLink: "tbd"
//         });

//         offer3 = OfferStruct({
//             takingOfferType: TakingOfferType.BlockOffer,
//             offerPrice: OfferPrice({
//                 offerPricingType: OfferPricingType.FixedPricing,
//                 unitPrice: 8e18,
//                 percentage: 0,
//                 percentageType: PercentageType.NoType
//             }),
//             specialAddresses: specialAddress, // Initialize array with 2 addresses
//             authorizationAddresses: authorizationAddresses, // Initialize array with 2 addresses
//             expiryTimestamp: block.timestamp + 2 days,
//             timelockPeriod: 0,
//             terms: "tbd",
//             commsLink: "tbd"
//         });

//         vm.startPrank(investor);
//         dotcV2.makeOffer(withdrawalAsset1, depositAsset, offer);
//         dotcV2.makeOffer(withdrawalAsset2, depositAsset, offer2);
//         dotcV2.makeOffer(withdrawalAsset3, depositAsset, offer3);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset3, offer3);
//         vm.stopPrank();
//     }

//     function createOffer(
//         TakingOfferType _takingOfferType,
//         uint256 _unitPrice
//     ) internal returns (OfferStruct memory) {
//         return
//             OfferStruct({
//                 takingOfferType: _takingOfferType,
//                 offerPrice: OfferPrice({
//                     offerPricingType: OfferPricingType.FixedPricing,
//                     unitPrice: _unitPrice,
//                     percentage: 0,
//                     percentageType: PercentageType.NoType
//                 }),
//                 specialAddresses: specialAddress,
//                 authorizationAddresses: authorizationAddresses,
//                 expiryTimestamp: block.timestamp + 2 days,
//                 timelockPeriod: 0,
//                 terms: "tbd",
//                 commsLink: "tbd"
//             });
//     }

//     // Comprehensive deposit test covering multiple users, amounts, and attempts to break contract
//     function testDepositFunctionalityWithMultipleAssetsAndOffers() public {
//         uint256 amount = 2 * 10 ** 18;
//         uint256 mint_amount = 10 * 10 ** 18;

//         // Mock different assets for multiple deposits
//         Asset memory withdrawalAsset1 = Asset({
//             assetType: AssetType.ERC20,
//             assetAddress: address(asset1),
//             amount: amount,
//             tokenId: 0,
//             assetPrice: AssetPrice(address(ChainLinkMockNVIDIA), 0, 0)
//         });

//         Asset memory withdrawalAsset2 = Asset({
//             assetType: AssetType.ERC20,
//             assetAddress: address(asset2),
//             amount: amount,
//             tokenId: 0,
//             assetPrice: AssetPrice(address(ChainLinkMockMSCRF), 0, 0)
//         });

//         Asset memory depositAsset = Asset({
//             assetType: AssetType.ERC20,
//             assetAddress: address(USDC),
//             amount: amount,
//             tokenId: 0,
//             assetPrice: AssetPrice(address(ChainLinkMockUSDC), 0, 0)
//         });

//         // Create offers for different assets
//         OfferStruct memory offer1 = OfferStruct({
//             takingOfferType: TakingOfferType.BlockOffer,
//             offerPrice: OfferPrice({
//                 offerPricingType: OfferPricingType.FixedPricing,
//                 unitPrice: 10e18,
//                 percentage: 0,
//                 percentageType: PercentageType.NoType
//             }),
//             specialAddresses: specialAddress,
//             authorizationAddresses: authorizationAddresses,
//             expiryTimestamp: block.timestamp + 2 days,
//             timelockPeriod: 0,
//             terms: "Offer 1 Terms",
//             commsLink: "Offer 1 Link"
//         });

//         OfferStruct memory offer2 = OfferStruct({
//             takingOfferType: TakingOfferType.BlockOffer,
//             offerPrice: OfferPrice({
//                 offerPricingType: OfferPricingType.FixedPricing,
//                 unitPrice: 5e18,
//                 percentage: 0,
//                 percentageType: PercentageType.NoType
//             }),
//             specialAddresses: specialAddress,
//             authorizationAddresses: authorizationAddresses,
//             expiryTimestamp: block.timestamp + 2 days,
//             timelockPeriod: 0,
//             terms: "Offer 2 Terms",
//             commsLink: "Offer 2 Link"
//         });

//         id1 = keccak256(abi.encodePacked("NVIDIA"));
//         id2 = keccak256(abi.encodePacked("MCFS"));
//         id3 = keccak256(abi.encodePacked("TESLA"));

//         // Initialize the price feeds
//         mockPyth.createPriceFeedUpdateData(
//             id1,
//             price1,
//             conf1,
//             expo1,
//             emaPrice1,
//             emaConf1,
//             publishTime1,
//             prevPublishTime1
//         );
//         mockPyth.createPriceFeedUpdateData(
//             id2,
//             price2,
//             conf2,
//             expo2,
//             emaPrice2,
//             emaConf2,
//             publishTime2,
//             prevPublishTime1
//         );
//         mockPyth.createPriceFeedUpdateData(
//             id3,
//             price3,
//             conf3,
//             expo3,
//             emaPrice3,
//             emaConf3,
//             publishTime3,
//             prevPublishTime1
//         );

//         // Make offers using the assets
//         vm.startPrank(investor);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer1);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);
//         vm.stopPrank();

//         // Update prices in the price feeds before deposits
//         mockPyth.updatePrice(id1, price1 + 5e7, expo1 + 3e7);
//         mockPyth.updatePrice(id2, price2 + 5e7, expo2 + 3e7);
//         mockPyth.updatePrice(id3, price3 + 5e7, expo3 + 3e7);

//         lzybravault.addPriceFeed(withdrawalAsset1.assetAddress, id3);

//         // Test successful deposit by user for offer1
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), amount);
//         lzybravault.deposit(amount, 1, mint_amount);
//         assertEq(
//             lzybra.balanceOf(user),
//             mint_amount,
//             "Deposit failed for user in offer 1"
//         );

//         // Update price again after deposit
//         mockPyth.updatePrice(id3, price1 + 6e7, expo3 + 4e7);

//         // Test partial deposit by user for offer2
//         USDC.approve(address(lzybravault), amount / 2);
//         lzybravault.deposit(amount / 2, 2, mint_amount / 2);
//         assertEq(
//             lzybra.balanceOf(user),
//             mint_amount + (mint_amount / 2),
//             "Partial deposit failed for user in offer 2"
//         );
//         vm.stopPrank();

//         // Test multiple users depositing for different offers and assets
//         vm.startPrank(investor);
//         USDC.approve(address(lzybravault), amount);
//         lzybravault.deposit(amount, 1, mint_amount);
//         assertEq(
//             lzybra.balanceOf(investor),
//             mint_amount,
//             "Deposit failed for investor in offer 1"
//         );

//         asset2.approve(address(lzybravault), amount / 2);
//         lzybravault.deposit(amount / 2, 2, mint_amount / 2);
//         assertEq(
//             lzybra.balanceOf(investor),
//             mint_amount + (mint_amount / 2),
//             "Partial deposit failed for investor in offer 2"
//         );
//         vm.stopPrank();

//         // Test invalid deposits: zero amount for offer1
//         vm.startPrank(user);
//         vm.expectRevert("Invalid amount");
//         lzybravault.deposit(0, 1, mint_amount);
//         vm.stopPrank();

//         // Test deposit with insufficient approval for offer2
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), amount / 2);
//         vm.expectRevert("ERC20: transfer amount exceeds allowance");
//         lzybravault.deposit(amount, 1, mint_amount);
//         vm.stopPrank();

//         // Test deposit exceeding allowed limit for offer1
//         vm.startPrank(user);
//         vm.expectRevert("Deposit exceeds allowed limit");
//         lzybravault.deposit(amount * 10, 1, mint_amount);
//         vm.stopPrank();

//         // Test deposit attempt by non-whitelisted user for offer2
//         address nonWhitelistedUser = address(0x123);
//         vm.startPrank(nonWhitelistedUser);
//         USDC.approve(address(lzybravault), amount);
//         vm.expectRevert("User not whitelisted");
//         lzybravault.deposit(amount, 2, mint_amount);
//         vm.stopPrank();
//     }

//     function testDepositWithMultiplePriceUpdates() public {
//         uint256 amount = 5 * 10 ** 18; // Amount to deposit
//         uint256 mintAmount = 20 * 10 ** 18; // Amount of LZYBRA tokens to mint
//         uint256 totalDeposited = 0; // Track total deposits for verification

//         // Mock deposits with different offers
//         for (int64 i = 0; i < 3; i++) {
//             // Prepare the asset for deposit
//             Asset memory depositAsset = Asset({
//                 assetType: AssetType.ERC20,
//                 assetAddress: address(USDC),
//                 amount: amount,
//                 tokenId: 0,
//                 assetPrice: AssetPrice(address(ChainLinkMockUSDC), 0, 0)
//             });

//             // Prepare the offer structure
//             OfferStruct memory offer = OfferStruct({
//                 takingOfferType: TakingOfferType.BlockOffer,
//                 offerPrice: OfferPrice({
//                     offerPricingType: OfferPricingType.FixedPricing,
//                     unitPrice: uint256(uint64(10 + (i * 5) * 1e7)), // Increment price for each offer
//                     percentage: 0,
//                     percentageType: PercentageType.NoType
//                 }),
//                 specialAddresses: specialAddress,
//                 authorizationAddresses: authorizationAddresses,
//                 expiryTimestamp: block.timestamp + 2 days,
//                 timelockPeriod: 0,
//                 terms: string(abi.encodePacked("Offer ", i, " Terms")),
//                 commsLink: string(abi.encodePacked("Offer ", i, " Link"))
//             });

//             // User deposits and mints tokens
//             vm.startPrank(user);
//             USDC.approve(address(lzybravault), amount);
//             lzybravault.deposit(amount, uint256(uint64(i + 1)), mintAmount);
//             totalDeposited += mintAmount;
//             assertEq(
//                 lzybra.balanceOf(user),
//                 totalDeposited,
//                 "Incorrect balance after deposit"
//             );
//             vm.stopPrank();

//             // Update price feeds after each deposit
//             mockPyth.updatePrice(
//                 id1,
//                 int64(i * (10 ** 7)),
//                 int64(i * (10 ** 7))
//             );
//         }

//         // Verify the total deposited amount and correct balances
//         assertEq(
//             lzybra.balanceOf(user),
//             totalDeposited,
//             "Total deposited balance mismatch"
//         );
//         assertEq(
//             lzybra.totalSupply(),
//             totalDeposited,
//             "Total supply mismatch after multiple deposits"
//         );

//         // Additional checks to ensure the logic holds after multiple deposits
//         uint256 expectedMintAmount = totalDeposited / 3; // Assume average minting calculation for validation
//         assertGt(
//             expectedMintAmount,
//             0,
//             "Expected mint amount should be greater than zero"
//         );
//     }

//     // Additional security penetration tests for deposit
//     function testPenetrationAttempts() public {
//         // Attempt to deposit by bypassing checks
//         vm.startPrank(user);

//         // Mock function call to a private/internal function
//         bytes memory payload = abi.encodeWithSignature("internalFunction()");
//         (bool success, ) = address(lzybravault).call(payload);
//         require(!success, "User bypassed private function"); // Using require for custom error message

//         // Attempt to deposit more than available balance
//         USDC.approve(address(lzybravault), AMOUNT * 2);
//         vm.expectRevert("ERC20: transfer amount exceeds balance");
//         lzybravault.deposit(AMOUNT * 2, 1, AMOUNT);

//         vm.stopPrank();
//     }

//     function testDepositWithExpiredOffer() public {
//     // Simulate expiration of the offer by advancing the block timestamp
//     vm.warp(block.timestamp + 3 days);

//     // Attempt to deposit after offer expiration
//     vm.startPrank(user);
//     USDC.approve(address(lzybravault), AMOUNT);

//     vm.expectRevert("Offer has expired");
//     lzybravault.deposit(AMOUNT, 1, AMOUNT);

//     vm.stopPrank();
// }

// function testReentrancyAttackOnDeposit() public {
//     ReentrancyAttacker attacker = new ReentrancyAttacker(address(lzybravault));

//     vm.startPrank(user);
//     USDC.approve(address(attacker), AMOUNT);

//     vm.expectRevert("ReentrancyGuard: reentrant call");
//     attacker.attackDeposit(AMOUNT, 1, AMOUNT);

//     vm.stopPrank();
// }

// // Helper contract to simulate a reentrancy attack on deposit



// function testDepositExceedingMaximumOfferLimit() public {
//     // Assuming the maximum deposit limit for an offer is 100e18
//     uint256 maxLimit = 100e18;
//     lzybravault.setOfferLimit(1, maxLimit); // Assuming `setOfferLimit` is available to set limits

//     vm.startPrank(user);
//     USDC.approve(address(lzybravault), maxLimit + 1);

//     // Attempt to deposit more than the maximum limit
//     vm.expectRevert("Deposit amount exceeds maximum limit");
//     lzybravault.deposit(maxLimit + 1, 1, maxLimit + 1);

//     vm.stopPrank();
// }


// function testDepositAcrossMultipleOffersSimultaneously() public {
//     uint256 amount = 10e18;

//     vm.startPrank(user);
//     USDC.approve(address(lzybravault), amount * 3);

//     // Deposit into offer 1
//     lzybravault.deposit(amount, 1, amount);
//     assertEq(lzybra.balanceOf(user), amount, "Incorrect balance after deposit in offer 1");

//     // Deposit into offer 2
//     lzybravault.deposit(amount, 2, amount);
//     assertEq(lzybra.balanceOf(user), amount * 2, "Incorrect balance after deposit in offer 2");

//     // Deposit into offer 3
//     lzybravault.deposit(amount, 3, amount);
//     assertEq(lzybra.balanceOf(user), amount * 3, "Incorrect balance after deposit in offer 3");

//     vm.stopPrank();
// }

// function testDepositWithMidTransactionPriceFeedUpdate() public {
//     uint256 amount = 5e18;

//     // Prepare and set the initial price
//     mockPyth.updatePrice(id1, price1, expo1);
//     lzybravault.addPriceFeed(address(USDC), id1);

//     // Start deposit transaction
//     vm.startPrank(user);
//     USDC.approve(address(lzybravault), amount);

//     // Update price feed in the middle of the deposit transaction
//     mockPyth.updatePrice(id1, price1 + 5e7, expo1 + 1e7);

//     lzybravault.deposit(amount, 1, amount);

//     assertEq(
//         lzybra.balanceOf(user),
//         amount,
//         "User balance after mid-transaction price feed update should be calculated based on updated price"
//     );

//     vm.stopPrank();
// }
// function testMultipleDepositsWithDynamicOfferAdjustments() public {
//     uint256 initialAmount = 10e18;
//     uint256 adjustedAmount = 15e18;

//     vm.startPrank(user);
//     USDC.approve(address(lzybravault), initialAmount);

//     // Initial deposit with current offer details
//     lzybravault.deposit(initialAmount, 1, initialAmount);
//     assertEq(lzybra.balanceOf(user), initialAmount, "User balance mismatch after initial deposit");

//     // Adjust the offer details
//     OfferStruct memory adjustedOffer = createOffer(TakingOfferType.BlockOffer, 12e18);
//     dotcV2.updateOffer(1, adjustedOffer);

//     // Approve new deposit amount
//     USDC.approve(address(lzybravault), adjustedAmount);

//     // Deposit again after offer adjustments
//     lzybravault.deposit(adjustedAmount, 1, adjustedAmount);
//     assertEq(
//         lzybra.balanceOf(user),
//         initialAmount + adjustedAmount,
//         "User balance mismatch after deposit with adjusted offer"
//     );

//     vm.stopPrank();
// }

// function testUnauthorizedAccessToDeposit() public {
//     address unauthorizedUser = address(0xABCD);

//     // Ensure unauthorized user is not in special addresses or authorizationAddresses
//     vm.startPrank(unauthorizedUser);
//     USDC.approve(address(lzybravault), AMOUNT);

//     vm.expectRevert("User not authorized for this offer");
//     lzybravault.deposit(AMOUNT, 1, AMOUNT);

//     vm.stopPrank();
// }


// }
// contract ReentrancyAttacker {
//     LzybraVault public vault;

//     constructor(address _vault) {
//         vault = LzybraVault(_vault);
//     }

//     fallback() external payable {
//         vault.deposit(1 ether, 1, 1 ether); // Attempt reentrant call within deposit
//     }

//     function attackDeposit(uint256 amount, uint256 offerId, uint256 mintAmount) public {
//         vault.deposit(amount, offerId, mintAmount);
//     }
// }