// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.19;

// import "forge-std/Test.sol";
// import {Asset, AssetType, AssetPrice, OfferFillType, PercentageType, OfferPrice, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType} from "../src/structures/DotcStructuresV2.sol";
// import "./BaseTest.sol";

// contract LzybraVaultWithdrawTest is BaseTest {
//     uint256 constant AMOUNT = 100e18;
//     uint256 constant WITHDRAW_AMOUNT = 50e18;
//     uint256 constant SMALL_AMOUNT = 1e18;

//     Asset depositAsset;
//     Asset withdrawalAsset1;
//     Asset withdrawalAsset2;
//     Asset withdrawalAsset3;

//     OfferStruct offer1;
//     OfferStruct offer2;
//     OfferStruct offer3;

//     bytes32 public id1;
//     bytes32 public id2;
//     bytes32 public id3;

//     // Setting up the test environment
//     function setUp() public override {
//         super.setUp();

//         // Mint initial balances for testing
//         USDC.mint(self, AMOUNT);
//         USDC.mint(investor, AMOUNT);
//         USDC.mint(user, AMOUNT);

//         // Approve assets for the vault
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         vm.stopPrank();

//         // Initialize price feed data for mocked assets
//         id1 = keccak256(abi.encodePacked("NVIDIA"));
//         id2 = keccak256(abi.encodePacked("MCSF"));
//         id3 = keccak256(abi.encodePacked("TESLA"));

//         // Setup price feeds with mocked data
//         initializePriceFeeds();

//         // Set up deposit and withdrawal assets with mocked price feeds
//         depositAsset = createAsset(address(USDC), address(ChainLinkMockUSDC), AMOUNT);
//         withdrawalAsset1 = createAsset(address(asset1), address(ChainLinkMockNVIDIA), AMOUNT);
//         withdrawalAsset2 = createAsset(address(asset2), address(ChainLinkMockMSCRF), AMOUNT);
//         withdrawalAsset3 = createAsset(address(asset3), address(ChainLinkMockUSDC), AMOUNT);

//         // Initialize offers with test-specific parameters
//         offer1 = createOffer(10e18);
//         offer2 = createOffer(5e18);
//         offer3 = createOffer(8e18);

//         // Make offers for testing scenarios
//         vm.startPrank(investor);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer1);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);
//         dotcV2.makeOffer(depositAsset, withdrawalAsset3, offer3);
//         vm.stopPrank();
//     }

//     // Helper function to initialize price feeds
//     function initializePriceFeeds() internal {
//         mockPyth.createPriceFeedUpdateData(id1, 10e7, 1e7, 0, 10e7, 1e7, uint64(block.timestamp), uint64(block.timestamp - 1));
//         mockPyth.createPriceFeedUpdateData(id2, 15e7, 2e7, 0, 15e7, 2e7, uint64(block.timestamp), uint64(block.timestamp - 1));
//         mockPyth.createPriceFeedUpdateData(id3, 20e7, 3e7, 0, 20e7, 3e7, uint64(block.timestamp), uint64(block.timestamp - 1));
//     }

//     // Helper function to create assets
//     function createAsset(address assetAddress, address priceFeed, uint256 amount) internal pure returns (Asset memory) {
//         return Asset({
//             assetType: AssetType.ERC20,
//             assetAddress: assetAddress,
//             amount: amount,
//             tokenId: 0,
//             assetPrice: AssetPrice(priceFeed, 0, 0)
//         });
//     }

//     // Helper function to create offers
//     function createOffer(uint256 unitPrice) internal view returns (OfferStruct memory) {
//         return OfferStruct({
//             takingOfferType: TakingOfferType.BlockOffer,
//             offerPrice: OfferPrice({
//                 offerPricingType: OfferPricingType.FixedPricing,
//                 unitPrice: unitPrice,
//                 percentage: 0,
//                 percentageType: PercentageType.NoType
//             }),
//             specialAddresses: specialAddress,
//             authorizationAddresses: authorizationAddresses,
//             expiryTimestamp: block.timestamp + 2 days,
//             timelockPeriod: 0,
//             terms: "tbd",
//             commsLink: "tbd"
//         });
//     }

//     // Test for a successful full withdrawal
//     function testSuccessfulFullWithdraw() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);
//         lzybravault.withdraw(1, AMOUNT);
        
//         assertEq(USDC.balanceOf(user), AMOUNT, "User balance should match deposited amount after full withdrawal");
//         assertEq(lzybravault.balanceOf(user), 0, "Vault balance for user should be zero after full withdrawal");
        
//         vm.stopPrank();
//     }

//     // Test for a partial withdrawal
//     function testPartialWithdraw() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);
        
//         lzybravault.withdraw(1, WITHDRAW_AMOUNT);
        
//         uint256 remainingBalance = AMOUNT - WITHDRAW_AMOUNT;
//         assertEq(USDC.balanceOf(user), WITHDRAW_AMOUNT, "User balance should reflect partial withdrawal");
//         assertEq(lzybravault.balanceOf(user), remainingBalance, "Vault balance should reflect remaining after partial withdrawal");
        
//         vm.stopPrank();
//     }

//     // Test for multiple withdrawals in sequence
//     function testMultipleSequentialWithdrawals() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);
        
//         lzybravault.withdraw(1, SMALL_AMOUNT);
//         assertEq(USDC.balanceOf(user), SMALL_AMOUNT, "Balance after first withdrawal should match small amount");
        
//         lzybravault.withdraw(1, WITHDRAW_AMOUNT);
//         assertEq(USDC.balanceOf(user), SMALL_AMOUNT + WITHDRAW_AMOUNT, "Balance after second withdrawal should be cumulative");

//         uint256 remainingBalance = AMOUNT - SMALL_AMOUNT - WITHDRAW_AMOUNT;
//         assertEq(lzybravault.balanceOf(user), remainingBalance, "Vault balance should match remaining after multiple withdrawals");
        
//         vm.stopPrank();
//     }

//     // Test for attempting to withdraw more than the deposited amount
//     function testWithdrawMoreThanDeposited() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);
        
//         vm.expectRevert("Withdraw amount exceeds balance");
//         lzybravault.withdraw(1, AMOUNT + 1);

//         vm.stopPrank();
//     }

//     // Test unauthorized withdrawal
//     function testUnauthorizedWithdraw() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);
//         vm.stopPrank();

//         // Try withdrawing from a different user
//         address attacker = makeAddr("attacker");
//         vm.startPrank(attacker);
//         vm.expectRevert("Only authorized users can withdraw");
//         lzybravault.withdraw(1, WITHDRAW_AMOUNT);
//         vm.stopPrank();
//     }

//     // Test reentrancy attack prevention on withdrawal
//     function testReentrancyAttack() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);

//         // Create a malicious contract to attempt reentrancy
//         ReentrancyAttacker attacker = new ReentrancyAttacker(address(lzybravault));

//         vm.expectRevert("ReentrancyGuard: reentrant call");
//         attacker.attack(1, WITHDRAW_AMOUNT);
//         vm.stopPrank();
//     }

//     // Test withdrawal during price feed manipulation
//     function testWithdrawalDuringPriceFeedManipulation() public {
//         vm.startPrank(user);
//         USDC.approve(address(lzybravault), AMOUNT);
//         lzybravault.deposit(AMOUNT, 1, AMOUNT);
//         vm.stopPrank();

//         // Manipulate the price feed
//         mockPyth.updatePrice(id1, 1e7, 1e7); // Lower price artificially

//         vm.startPrank(user);
//         lzybravault.withdraw(1, AMOUNT);
        
//         assertEq(USDC.balanceOf(user), AMOUNT, "User balance after manipulated price withdrawal should be consistent");

//         vm.stopPrank();
//     }

//     // Helper contract to simulate a reentrancy attack

// }
//     contract ReentrancyAttacker {
//         LzybraVault public vault;

//         constructor(address _vault) {
//             vault = LzybraVault(_vault);
//         }

//         fallback() external payable {
//             vault.withdraw(1, 10 ether); // Attempt to reenter during withdrawal
//         }

//         function attack(uint256 offerId, uint256 amount) public {
//             vault.withdraw(offerId, amount);
//         }
//     }