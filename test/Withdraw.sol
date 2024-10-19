// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Asset, AssetType, AssetPrice, OfferFillType, PercentageType, OfferPrice, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType} from "../src/structures/DotcStructuresV2.sol";
import "./BaseTest.sol";

contract LzybraVaultWithdrawTest is BaseTest {
    uint256 AMOUNT = 100e18;
    uint256 WITHDRAW_AMOUNT = 50e18;

    Asset depositAsset;
    Asset withdrawalAsset1;
    Asset withdrawalAsset2;
    Asset withdrawalAsset3;

    OfferStruct offer1;
    OfferStruct offer2;
    OfferStruct offer3;

    bytes32 public id1;
    bytes32 public id2;
    bytes32 public id3;

    // Setting up the test environment
    function setUp() public override {
        super.setUp();

        // Mint initial balances
        USDC.mint(self, AMOUNT);
        USDC.mint(investor, AMOUNT);
        USDC.mint(user, AMOUNT);

        // Approve assets for the vault
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        vm.stopPrank();

        // Initialize price feed data
        id1 = keccak256(abi.encodePacked("NVIDIA"));
        id2 = keccak256(abi.encodePacked("MCSF"));
        id3 = keccak256(abi.encodePacked("TESLA"));

        // Setup price feeds
        initializePriceFeeds();

        // Create deposit and withdrawal assets
        depositAsset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(USDC),
            amount: AMOUNT,
            tokenId: 0,
            assetPrice: AssetPrice(address(ChainLinkMockUSDC), 0, 0)
        });

        withdrawalAsset1 = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(asset1),
            amount: AMOUNT,
            tokenId: 0,
            assetPrice: AssetPrice(address(ChainLinkMockNVIDIA), 0, 0)
        });

        // Initialize offers
        offer1 = createOffer(10e18);
        offer2 = createOffer(5e18);
        offer3 = createOffer(8e18);

        // Make offers for testing
        vm.startPrank(investor);
        dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer1);
        dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);
        dotcV2.makeOffer(depositAsset, withdrawalAsset3, offer3);
        vm.stopPrank();
    }

    // Helper function to initialize price feeds
    function initializePriceFeeds() internal {
        mockPyth.createPriceFeedUpdateData(id1, 10e7, 1e7, 0, 10e7, 1e7, uint64(block.timestamp), uint64(block.timestamp - 1));
        mockPyth.createPriceFeedUpdateData(id2, 15e7, 2e7, 0, 15e7, 2e7, uint64(block.timestamp), uint64(block.timestamp - 1));
        mockPyth.createPriceFeedUpdateData(id3, 20e7, 3e7, 0, 20e7, 3e7, uint64(block.timestamp), uint64(block.timestamp - 1));
    }

    // Helper function to create offers
    function createOffer(uint256 unitPrice) internal returns (OfferStruct memory) {
        return OfferStruct({
            takingOfferType: TakingOfferType.BlockOffer,
            offerPrice: OfferPrice({
                offerPricingType: OfferPricingType.FixedPricing,
                unitPrice: unitPrice,
                percentage: 0,
                percentageType: PercentageType.NoType
            }),
            specialAddresses: specialAddress,
            authorizationAddresses: authorizationAddresses,
            expiryTimestamp: block.timestamp + 2 days,
            timelockPeriod: 0,
            terms: "tbd",
            commsLink: "tbd"
        });
    }

    // Test for a successful full withdrawal
    function testSuccessfulFullWithdraw() public {
        // Deposit funds first
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        lzybravault.deposit(AMOUNT, 1, AMOUNT);

        // Now withdraw the full amount
        lzybravault.withdraw(1, AMOUNT);
        
        // Check user’s balance after withdrawal
        assertEq(USDC.balanceOf(user), AMOUNT, "Incorrect user balance after withdrawal");

        vm.stopPrank();
    }

    // Test for partial withdrawal
    function testPartialWithdraw() public {
        // Deposit funds first
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        lzybravault.deposit(AMOUNT, 1, AMOUNT);

        // Withdraw half of the amount
        lzybravault.withdraw(1, WITHDRAW_AMOUNT);

        // Check balances after partial withdrawal
        assertEq(USDC.balanceOf(user), WITHDRAW_AMOUNT, "Incorrect user balance after partial withdrawal");
        assertGt(AMOUNT, USDC.balanceOf(user), "Expected partial balance after withdrawal");

        vm.stopPrank();
    }

    // Test for withdrawing more than the deposited amount
    function testWithdrawMoreThanDeposited() public {
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        lzybravault.deposit(AMOUNT, 1, AMOUNT);

        // Attempt to withdraw more than deposited
        vm.expectRevert("Withdraw amount exceeds balance");
        lzybravault.withdraw(1, AMOUNT + 1);

        vm.stopPrank();
    }

    // Test unauthorized withdrawal
    function testUnauthorizedWithdraw() public {
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        lzybravault.deposit(AMOUNT, 1, AMOUNT);
        vm.stopPrank();

        // Try withdrawing from a different user
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.expectRevert("Only authorized users can withdraw");
        lzybravault.withdraw(1, WITHDRAW_AMOUNT);
        vm.stopPrank();
    }

    // Test Reentrancy attack prevention on withdrawal
    function testReentrancyAttack() public {
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        lzybravault.deposit(AMOUNT, 1, AMOUNT);

        // Create a malicious contract to attempt reentrancy
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(lzybravault));

        vm.expectRevert("ReentrancyGuard: reentrant call");
        attacker.attack(1, WITHDRAW_AMOUNT);
        vm.stopPrank();
    }

    // Test price feed manipulation on withdrawal
    function testPriceFeedManipulation() public {
        // Deposit funds
        vm.startPrank(user);
        USDC.approve(address(lzybravault), AMOUNT);
        lzybravault.deposit(AMOUNT, 1, AMOUNT);
        vm.stopPrank();

        // Attacker manipulates the price feed
        mockPyth.updatePrice(id1, 1e7, 1e7); // Lower the price artificially

        // Attempt to withdraw at the manipulated price
        vm.startPrank(user);
        lzybravault.withdraw(1, AMOUNT);

        // Check if user received less due to price manipulation
        assertEq(USDC.balanceOf(user), AMOUNT, "Withdraw amount should not be impacted by price manipulation");

        vm.stopPrank();
    }

    // Helper contract to simulate a reentrancy attack
    contract ReentrancyAttacker {
        LzybraVault public vault;

        constructor(address _vault) {
            vault = LzybraVault(_vault);
        }

        fallback() external payable {
            vault.withdraw(1, 10 ether); // Attempt to reenter during withdrawal
        }

        function attack(uint256 offerId, uint256 amount) public {
            vault.withdraw(offerId, amount);
        }
    }
}
