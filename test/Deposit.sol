// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { Asset, AssetType, OfferFillType, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType } from "../src/structures/DotcStructuresV2.sol";
import "./BaseTest.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DepositTest is BaseTest {
    uint256 initialBalance = 1000e18; // User starts with 1000 USDC tokens
    uint256 assetAmount = 100e18; // Deposit amount of 100 USDC tokens
    uint256 fakeOfferPrice = 1e18; // Example price

    // Mock withdrawal asset and offer
    Asset withdrawalAsset;
    OfferStruct offer;

    function setUp() public {
        // Setup the mocks


        // Mint USDC tokens to the user
        USDC.mint(self, initialBalance);
        USDC.mint(investor, initialBalance); // Optional owner balance

        // Approve the lzybravault to spend user's USDC
        vm.startPrank(user);
        USDC.approve(address(lzybravault), initialBalance);
        vm.stopPrank();

        // Setup a mock withdrawal asset
        withdrawalAsset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(asset1), // Fake asset for testing
            amount: 10e18,
            reserved: 0
        });

        USDC.approve(address(lzybravault), initialBalance);
        // Setup a mock offer
        offer = OfferStruct({
            id: 1,
            depositAsset: withdrawalAsset, 
            withdrawalAsset: withdrawalAsset, 
            offerPrice: OfferPrice({ unitPrice: fakeOfferPrice })
        });
    }

    function testDeposit() public {
        // Prank user making the deposit
        vm.startPrank(user);

        // Call the deposit function
        lzybravault.Deposit(assetAmount, withdrawalAsset, offer);

        // Check user balance of USDC after deposit
        assertEq(USDC.balanceOf(user), initialBalance - assetAmount, "User collateral balance not deducted correctly");

        // Check if LZYBRA tokens were minted based on the deposit
        uint256 mintAmount = assetAmount * fakeOfferPrice;
        assertEq(lzybra.balanceOf(user), mintAmount, "Incorrect LZYBRA tokens minted");

        // Check if the event was emitted correctly
        vm.expectEmit(true, true, true, true);
        emit DepositAsset(user, address(USDC), assetAmount);

        vm.stopPrank();
    }

    function testInvalidDepositAmount() public {
        // Prank user making an invalid deposit (0 amount)
        vm.startPrank(user);

        // Expect revert when depositing 0
        vm.expectRevert("Deposit amount must be greater than 0");
        lzybravault.Deposit(0, withdrawalAsset, offer);

        vm.stopPrank();
    }

    function testMakeOfferCalledInDOTCV2() public {
        // Prank user making a deposit
        vm.startPrank(user);

        // Expect the makeOffer function to be called in DOTCV2
        vm.expectCall(address(dotcV2), abi.encodeWithSelector(dotcV2.makeOffer.selector, withdrawalAsset, withdrawalAsset, offer));
        lzybravault.Deposit(assetAmount, withdrawalAsset, offer);

        vm.stopPrank();
    }

    function testMintLZYBRACalculation() public {
        // Prank user making the deposit
        vm.startPrank(user);

        // Call the deposit function
        lzybravault.Deposit(assetAmount, withdrawalAsset, offer);

        // Calculate expected LZYBRA minted amount
        uint256 expectedMintAmount = assetAmount * fakeOfferPrice;

        // Check if the LZYBRA tokens minted match the expected amount
        assertEq(lzybra.balanceOf(user), expectedMintAmount, "LZYBRA mint amount incorrect");

        vm.stopPrank();
    }

    function testDepositWithNoApproval() public {
        // Reset prank and remove approval for lzybravault
        vm.startPrank(user);
        USDC.approve(address(lzybravault), 0);

        // Expect revert when approval is not set
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        lzybravault.Deposit(assetAmount, withdrawalAsset, offer);

        vm.stopPrank();
    }
}
