// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    uint256 constant COLLATERAL_AMOUNT = 100e18;
    uint256 constant BORROW_AMOUNT = 50e18;
    uint256 constant REDUCED_PRICE = 5e7; // Lower price to trigger liquidation
    bytes32 public collateralAssetId;

    function setUp() public override {
        super.setUp();

        // Initialize the price feed ID for the collateral asset
        collateralAssetId = keccak256(abi.encodePacked("COLLATERAL_ASSET"));

        // Set initial price feed for the collateral asset
        mockPyth.createPriceFeedUpdateData(
            collateralAssetId,
            int64(10e7), // Initial price
            uint64(1e7), // Confidence interval
            int32(0),    // Exponent
            int64(10e7), // EMA price
            uint64(1e7), // EMA confidence
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
    }

    function testLiquidationTriggeredByPriceDrop() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Step 2: Mock a price drop to trigger under-collateralization
        mockPyth.updatePrice(collateralAssetId, int64(REDUCED_PRICE), int32(0));

        // Verify that collateral value has dropped below the safe threshold
        uint256 collateralRatio = lzybravault.getCollateralRatio(user);
        assertLt(collateralRatio, configurator.getSafeCollateralRatio(), "Collateral ratio should be below safe threshold");

        // Step 3: Liquidator attempts liquidation
        vm.startPrank(investor);
        uint256 liquidateAmount = BORROW_AMOUNT / 2;

        // Track balances before liquidation
        uint256 investorInitialBalance = USDC.balanceOf(investor);
        uint256 userInitialDebt = lzybravault.getBorrowed(user, address(asset1));

        lzybravault.liquidation(
            investor,
            user,
            liquidateAmount,
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(asset1),
                amount: liquidateAmount,
                tokenId: 0,
                assetPrice: AssetPrice(address(mockPyth), 0, 0)
            }),
            new bytes // Empty price update payload
        );

        // Verify liquidation results
        uint256 investorPostBalance = USDC.balanceOf(investor);
        uint256 userPostDebt = lzybravault.getBorrowed(user, address(asset1));

        // Check that investor receives collateral as reward
        assertGt(investorPostBalance, investorInitialBalance, "Investor should receive collateral after liquidation");

        // Check that user debt is partially cleared
        assertLt(userPostDebt, userInitialDebt, "User debt should reduce after partial liquidation");
        
        vm.stopPrank();
    }

    function testFullDebtRepayment() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // User initiates repayment of full debt
        lzybravault.repayingDebt(user, address(asset1), BORROW_AMOUNT);

        // Check that user’s debt is fully cleared
        uint256 remainingDebt = lzybravault.getBorrowed(user, address(asset1));
        assertEq(remainingDebt, 0, "Debt should be fully repaid");

        vm.stopPrank();
    }

    function testPartialDebtRepayment() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // User initiates partial repayment
        uint256 repaymentAmount = BORROW_AMOUNT / 2;
        lzybravault.repayingDebt(user, address(asset1), repaymentAmount);

        // Check that debt is partially reduced
        uint256 remainingDebt = lzybravault.getBorrowed(user, address(asset1));
        assertEq(remainingDebt, BORROW_AMOUNT - repaymentAmount, "Debt should reduce by repayment amount");

        vm.stopPrank();
    }

    function testFailedLiquidationDueToSufficientCollateral() public {
        // User deposits collateral but price remains stable (no under-collateralization)
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Attempt liquidation (should revert due to sufficient collateral)
        vm.startPrank(investor);
        vm.expectRevert("Collateral ratio above threshold");
        lzybravault.liquidation(
            investor,
            user,
            BORROW_AMOUNT,
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(asset1),
                amount: COLLATERAL_AMOUNT,
                tokenId: 0,
                assetPrice: AssetPrice(address(mockPyth), 0, 0)
            }),
            new bytes
        );
        vm.stopPrank();
    }

    function testFullLiquidationAfterSeverePriceDrop() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Step 2: Severe price drop simulation
        mockPyth.updatePrice(collateralAssetId, int64(2e7), int32(0)); // Extreme drop to trigger full liquidation

        // Step 3: Liquidator performs full liquidation
        vm.startPrank(investor);
        uint256 initialInvestorBalance = USDC.balanceOf(investor);

        lzybravault.liquidation(
            investor,
            user,
            BORROW_AMOUNT,
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(asset1),
                amount: COLLATERAL_AMOUNT,
                tokenId: 0,
                assetPrice: AssetPrice(address(mockPyth), 0, 0)
            }),
            new bytes 
        );

        // Verify that the user's debt is fully cleared
        uint256 remainingDebt = lzybravault.getBorrowed(user, address(asset1));
        assertEq(remainingDebt, 0, "User debt should be zero after full liquidation");

        // Investor should receive full collateral as reward
        uint256 finalInvestorBalance = USDC.balanceOf(investor);
        assertGt(finalInvestorBalance, initialInvestorBalance, "Investor should receive collateral after full liquidation");

        vm.stopPrank();
    }
      function testPartialDebtRepayment() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Verify initial debt amount
        uint256 initialDebt = lzybravault.getBorrowed(user, address(borrowedAsset.assetAddress));
        assertEq(initialDebt, BORROW_AMOUNT, "Initial debt should match the borrowed amount");

        // Step 2: User repays partial debt
        uint256 repaymentAmount = BORROW_AMOUNT / 2;
        USDC.approve(address(lzybravault), repaymentAmount);
        lzybravault.repayDebt(user, borrowedAsset.assetAddress, repaymentAmount);

        // Verify that the debt has been partially repaid
        uint256 remainingDebt = lzybravault.getBorrowed(user, borrowedAsset.assetAddress);
        assertEq(remainingDebt, BORROW_AMOUNT - repaymentAmount, "Debt should be partially repaid");

        vm.stopPrank();
    }

    // Test over-repayment scenario where the user tries to repay more than the debt amount
    function testOverRepayment() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Attempt to repay more than the actual debt amount
        uint256 repaymentAmount = BORROW_AMOUNT * 2;
        USDC.approve(address(lzybravault), repaymentAmount);
        vm.expectRevert("Repayment exceeds debt amount");
        lzybravault.repayDebt(user, borrowedAsset.assetAddress, repaymentAmount);

        vm.stopPrank();
    }

    // Test unauthorized repayment scenario
    function testUnauthorizedRepayment() public {
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);
        vm.stopPrank();

        // Attempt to repay debt from an unauthorized address
        address unauthorizedUser = makeAddr("unauthorized");
        vm.startPrank(unauthorizedUser);

        uint256 repaymentAmount = BORROW_AMOUNT;
        USDC.approve(address(lzybravault), repaymentAmount);
        vm.expectRevert("Unauthorized repayment");
        lzybravault.repayDebt(user, borrowedAsset.assetAddress, repaymentAmount);

        vm.stopPrank();
    }


function testCollateralRestorationAfterFullRepayment() public {
    // Step 1: User deposits collateral and borrows
    vm.startPrank(user);
    USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
    lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

    // Step 2: Fully repay the debt
    lzybravault.repayDebt(user, address(USDC), BORROW_AMOUNT);

    // Step 3: Verify collateral balance after full repayment
    uint256 collateralBalance = lzybravault.getCollateralBalance(user);
    assertEq(collateralBalance, COLLATERAL_AMOUNT, "Collateral should be fully restored after full debt repayment");

    vm.stopPrank();
}

function testLiquidationWithInsufficientDebt() public {
    // Step 1: User deposits collateral and borrows
    vm.startPrank(user);
    USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
    lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

    // Partially repay the debt to an amount below the liquidation threshold
    uint256 repaymentAmount = BORROW_AMOUNT - (BORROW_AMOUNT / 4);
    lzybravault.repayDebt(user, address(USDC), repaymentAmount);

    // Step 2: Attempt liquidation, which should fail
    vm.startPrank(investor);
    vm.expectRevert("Debt amount insufficient for liquidation");
    lzybravault.liquidation(
        investor,
        user,
        BORROW_AMOUNT / 2,
        Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(asset1),
            amount: BORROW_AMOUNT / 2,
            tokenId: 0,
            assetPrice: AssetPrice(address(mockPyth), 0, 0)
        }),
        new bytes
    );

    vm.stopPrank();
}
function testLiquidationAfterPartialRepayment() public {
    // Step 1: User deposits collateral and borrows
    vm.startPrank(user);
    USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
    lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

    // Step 2: Partial debt repayment
    uint256 partialRepayment = BORROW_AMOUNT / 2;
    lzybravault.repayDebt(user, address(USDC), partialRepayment);

    // Step 3: Price drop to trigger liquidation condition
    mockPyth.updatePrice(collateralAssetId, int64(REDUCED_PRICE), int32(0));

    // Step 4: Liquidator attempts partial liquidation
    vm.startPrank(investor);
    lzybravault.liquidation(
        investor,
        user,
        BORROW_AMOUNT / 4,
        Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(asset1),
            amount: COLLATERAL_AMOUNT / 2,
            tokenId: 0,
            assetPrice: AssetPrice(address(mockPyth), 0, 0)
        }),
        new bytes
    );

    // Verify that debt has been reduced after liquidation
    uint256 remainingDebt = lzybravault.getBorrowed(user, address(asset1));
    assertEq(remainingDebt, partialRepayment - (BORROW_AMOUNT / 4), "Debt should be reduced by liquidation amount");

    vm.stopPrank();
}
function testExactDebtRepayment() public {
    // Step 1: User deposits collateral and borrows
    vm.startPrank(user);
    USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
    lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

    // Step 2: Repay exactly the borrowed amount
    USDC.approve(address(lzybravault), BORROW_AMOUNT);
    lzybravault.repayDebt(user, address(USDC), BORROW_AMOUNT);

    // Verify that the debt is exactly cleared
    uint256 remainingDebt = lzybravault.getBorrowed(user, address(asset1));
    assertEq(remainingDebt, 0, "Debt should be exactly zero after full repayment");

    vm.stopPrank();
}


}
