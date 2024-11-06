// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    uint256 constant COLLATERAL_AMOUNT = 100e18;
    uint256 constant BORROW_AMOUNT = 50e18;
    uint256 constant REDUCED_PRICE = 5e7; // Lower price to trigger liquidation
    bytes32 public collateralAssetId;
    bytes32 public collateralAssetId;
    bytes32 public NvidiaAssetId;
    bytes32 public TeslaAssetId;
    bytes32 public MicroAssetId;
    bytes32 public collateralPriceUpdate;
    bytes32 public NvidiaPriceUpdate;
    bytes32 public TeslaPriceUpdate;
    bytes32 public MicroPriceUpdate;
    bytes32 public nvidiaOfferId;
    bytes32 public microsoftOfferId;
    bytes32 public teslaOfferId;

    function setUp() public override  {
    super.setUp();

    // Initialize the price feed IDs for various assets
    collateralAssetId = keccak256(abi.encodePacked("COLLATERAL_ASSET"));
    NvidiaAssetId = keccak256(abi.encodePacked("NVIDIA_ASSET"));
    TeslaAssetId = keccak256(abi.encodePacked("TESLA_ASSET"));
    MicroAssetId = keccak256(abi.encodePacked("MICROSOFT_ASSET"));

    // Set initial price updates for each asset using mockPyth
    collateralPriceUpdate = mockPyth.createPriceFeedUpdateData(
        collateralAssetId,
        int64(1e7), 
        uint64(1e7),
        int32(0),
        int64(1e7),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );

    NvidiaPriceUpdate = mockPyth.createPriceFeedUpdateData(
        NvidiaAssetId,
        int64(160e7),
        uint64(1e7),
        int32(0),
        int64(160e7),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );

    TeslaPriceUpdate = mockPyth.createPriceFeedUpdateData(
        TeslaAssetId,
        int64(150e7),
        uint64(1e7),
        int32(0),
        int64(150e7),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );

    MicroPriceUpdate = mockPyth.createPriceFeedUpdateData(
        MicroAssetId,
        int64(14e7),
        uint64(1e7),
        int32(0),
        int64(14e7),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );

    // Create offers for different asset pairs to USDC


       dotcV2.makeOffer(
        Asset({ assetType: AssetType.ERC20, assetAddress: address(asset1), amount: 500 * 10 ** 18, tokenId: 0 }),
        Asset({ assetType: AssetType.ERC20, assetAddress: address(USDC), amount: 160000 * 10 ** 6, tokenId: 0 }),
        OfferStruct({
            maker: address(this),
            offerPricingType: OfferPricingType.FixedPricing,
            takingOfferType: TakingOfferType.OpenOffer,
            offerPrice: OfferPrice({ offerPricingType: OfferPricingType.FixedPricing, unitPrice: 160 * 10 ** 18 }),
            expiryTimestamp: block.timestamp + 1 days,
            timelockPeriod: 1 hours,
            terms: "Terms for NVIDIA offer",
            commsLink: "http://example.com",
            specialAddresses: specialAddress,
            authorizationAddresses: authorizationAddresses
        })
    );
    nvidiaOfferId = dotcV2.currentOfferId - 1;

    // Create an offer for MICROSOFT and store its offerId
    dotcV2.makeOffer(
        Asset({ assetType: AssetType.ERC20, assetAddress: address(asset2), amount: 500 * 10 ** 18, tokenId: 0 }),
        Asset({ assetType: AssetType.ERC20, assetAddress: address(USDC), amount: 16800 * 10 ** 6, tokenId: 0 }),
        OfferStruct({
            maker: address(this),
            offerPricingType: OfferPricingType.FixedPricing,
            takingOfferType: TakingOfferType.OpenOffer,
            offerPrice: OfferPrice({ offerPricingType: OfferPricingType.FixedPricing, unitPrice: 14 * 10 ** 18 }),
            expiryTimestamp: block.timestamp + 1 days,
            timelockPeriod: 1 hours,
            terms: "Terms for MICROSOFT offer",
            commsLink: "http://example.com",
            specialAddresses: specialAddress,
            authorizationAddresses: authorizationAddresses
        })
    );
    microsoftOfferId = dotcV2.currentOfferId - 1;

    // Create an offer for TESLA and store its offerId
    dotcV2.makeOffer(
        Asset({ assetType: AssetType.ERC20, assetAddress: address(asset3), amount: 500 * 10 ** 18, tokenId: 0 }),
        Asset({ assetType: AssetType.ERC20, assetAddress: address(USDC), amount: 150000 * 10 ** 6, tokenId: 0 }),
        OfferStruct({
            maker: address(this),
            offerPricingType: OfferPricingType.FixedPricing,
            takingOfferType: TakingOfferType.OpenOffer,
            offerPrice: OfferPrice({ offerPricingType: OfferPricingType.FixedPricing, unitPrice: 150 * 10 ** 18 }),
            expiryTimestamp: block.timestamp + 1 days,
            timelockPeriod: 2 hours,
            terms: "Terms for TESLA offer",
            commsLink: "http://example.com",
            specialAddresses: specialAddress,
            authorizationAddresses: authorizationAddresses
        })
    );
    teslaOfferId = dotcV2.currentOfferId - 1;
}

/**
 * @dev Helper function to create offers from multiple assets to USDC.
 */



    function testLiquidationTriggeredByPriceDrop() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Step 2: Mock a price drop to trigger under-collateralization
        mockPyth.updatePrice(collateralAssetId, int64(REDUCED_PRICE), int32(0));

        // Verify that collateral value has dropped below the safe threshold
        uint256 collateralRatio = lzybravault.getCollateralRatio(user);
        assertLt(
            collateralRatio,
            configurator.getSafeCollateralRatio(),
            "Collateral ratio should be below safe threshold"
        );

        // Step 3: Liquidator attempts liquidation
        vm.startPrank(investor);
        uint256 liquidateAmount = BORROW_AMOUNT / 2;

        // Track balances before liquidation
        uint256 investorInitialBalance = USDC.balanceOf(investor);
        uint256 userInitialDebt = lzybravault.getBorrowed(
            user,
            address(asset1)
        );

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
        assertGt(
            investorPostBalance,
            investorInitialBalance,
            "Investor should receive collateral after liquidation"
        );

        // Check that user debt is partially cleared
        assertLt(
            userPostDebt,
            userInitialDebt,
            "User debt should reduce after partial liquidation"
        );

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
        assertEq(
            remainingDebt,
            BORROW_AMOUNT - repaymentAmount,
            "Debt should reduce by repayment amount"
        );

        vm.stopPrank();
    }

    function setupWithdrawalAssetAndOffer(
        address depositAssetAddress, // Address of the deposit asset
        uint256 depositAmount, // Amount of the deposit asset
        address withdrawalAssetAddress, // Address of the withdrawal asset
        uint256 withdrawalAmount, // Amount of the withdrawal asset
        uint256 unitPrice, // Price per unit in terms of withdrawal asset
        uint256 expiryDuration, // Duration until the offer expires
        uint256 timelockDuration // Duration of the timelock period
    ) internal returns (Asset memory withdrawalAsset, DotcOffer memory offer) {
        // Step 1: Define the withdrawal asset dynamically
        withdrawalAsset = Asset({
            assetType: AssetType.ERC20, // Specify asset type as ERC20
            assetAddress: withdrawalAssetAddress, // Dynamic address for withdrawal asset
            amount: withdrawalAmount, // Dynamic amount for withdrawal asset
            tokenId: 0 // Token ID set to 0 for ERC20 assets
        });

        // Step 2: Define the offer details dynamically
        offer = DotcOffer({
            maker: msg.sender, // Address creating the offer
            isFullType: true, // Set to true if full amount is offered
            isFullyTaken: false, // Set to false initially
            depositAsset: Asset({
                assetType: AssetType.ERC20,
                assetAddress: depositAssetAddress, // Dynamic address for deposit asset
                amount: depositAmount, // Dynamic amount for deposit asset
                tokenId: 0 // Token ID set to 0 for ERC20 assets
            }),
            withdrawalAsset: withdrawalAsset, // The withdrawal asset defined above
            availableAmount: depositAmount, // Available amount for trading (set to depositAmount)
            unitPrice: unitPrice, // Dynamic price per unit in terms of withdrawal asset
            specialAddress: address(0), // No specific address restriction
            expiryTime: block.timestamp + expiryDuration, // Dynamic expiry time based on duration
            timelockPeriod: timelockDuration // Dynamic timelock period
        });

        return (withdrawalAsset, offer);
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

   
    function testPartialDebtRepayment() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Verify initial debt amount
        uint256 initialDebt = lzybravault.getBorrowed(
            user,
            address(borrowedAsset.assetAddress)
        );
        assertEq(
            initialDebt,
            BORROW_AMOUNT,
            "Initial debt should match the borrowed amount"
        );

        // Step 2: User repays partial debt
        uint256 repaymentAmount = BORROW_AMOUNT / 2;
        USDC.approve(address(lzybravault), repaymentAmount);
        lzybravault.repayDebt(
            user,
            borrowedAsset.assetAddress,
            repaymentAmount
        );

        // Verify that the debt has been partially repaid
        uint256 remainingDebt = lzybravault.getBorrowed(
            user,
            borrowedAsset.assetAddress
        );
        assertEq(
            remainingDebt,
            BORROW_AMOUNT - repaymentAmount,
            "Debt should be partially repaid"
        );

        vm.stopPrank();
    }

    // Test over-repayment scenario where the user tries to repay more than the debt amount

    // Test unauthorized repayment scenario
    function testOverRepayment() public {
        // Step 1: User deposits collateral and borrows
        vm.startPrank(user);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, 1, BORROW_AMOUNT);

        // Attempt to repay more than the actual debt amount
        uint256 repaymentAmount = BORROW_AMOUNT * 2;
        USDC.approve(address(lzybravault), repaymentAmount);
        vm.expectRevert("Repayment exceeds debt amount");
        lzybravault.repayingDebt(
            user,
            address(asset1), // NVIDIA asset as collateral
            repaymentAmount,
            new bytes // Empty price update for this test
        );

        vm.stopPrank();
    }

    function testUnauthorizedRepayment() public {
        // Configure assets and offer
        (
            Asset memory withdrawalAsset,
            DotcOffer memory offer
        ) = setupWithdrawalAssetAndOffer(
                address(asset1), // deposit asset (NVIDIA)
                500 * 10 ** 18, // deposit amount
                address(asset2), // withdrawal asset (MICROSOFT)
                1000 * 10 ** 18, // withdrawal amount
                2 * 10 ** 18, // unit price
                1 days, // expiry duration
                1 hours // timelock duration
            );

        // Price update data for collateral asset
        bytes memory priceUpdateData = mockPyth.createPriceFeedUpdateData(
            NvidiaAssetId,
            int64(1e8),
            uint64(1e7),
            int32(0),
            int64(1e8),
            uint64(1e7),
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        bytes[] memory priceUpdate = new bytes[](1);
        priceUpdate[0] = priceUpdateData;

        // Step 1: User A deposits collateral and creates an offer
        vm.startPrank(userA);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, withdrawalAsset, offer);
        vm.stopPrank();

        // Step 2: User B takes the offer and borrows
        vm.startPrank(userB);
        lzybravault.deposit(
            COLLATERAL_AMOUNT,
            1, // Offer ID placeholder
            BORROW_AMOUNT,
            true,
            105e18
        );
        vm.stopPrank();

        // Attempt unauthorized repayment
        address unauthorizedUser = makeAddr("unauthorized");
        vm.startPrank(unauthorizedUser);
        uint256 repaymentAmount = BORROW_AMOUNT;
        USDC.approve(address(lzybravault), repaymentAmount);
        vm.expectRevert("Unauthorized repayment");
        lzybravault.repayingDebt(
            userB,
            address(asset1), // Repaying NVIDIA asset
            repaymentAmount,
            priceUpdate
        );

        vm.stopPrank();
    }

   function testFullLiquidationAfterSeverePriceDrop() public {
    // Setup assets and offer
    (
        Asset memory withdrawalAsset,
        DotcOffer memory offer
    ) = setupWithdrawalAssetAndOffer(
            address(asset1), // deposit asset (NVIDIA)
            500 * 10 ** 18, // deposit amount
            address(asset3), // withdrawal asset (TESLA)
            1000 * 10 ** 18, // withdrawal amount
            2 * 10 ** 18, // unit price
            1 days, // expiry duration
            1 hours // timelock duration
        );

    // Initial price update data for NVIDIA asset
    bytes memory priceUpdateData = mockPyth.createPriceFeedUpdateData(
        NvidiaAssetId,
        int64(1e8),
        uint64(1e7),
        int32(0),
        int64(1e8),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );
    bytes;
    priceUpdate[0] = priceUpdateData;

    // User A deposits collateral and creates offer
    vm.startPrank(userA);
    USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
    lzybravault.deposit(COLLATERAL_AMOUNT, withdrawalAsset, offer);
    vm.stopPrank();

    // User B takes the offer and borrows
    vm.startPrank(userB);
    lzybravault.deposit(
        COLLATERAL_AMOUNT,
        1, // Offer ID placeholder
        BORROW_AMOUNT,
        true,
        105e18
    );
    vm.stopPrank();

    // Severe price drop for NVIDIA asset to trigger full liquidation
    mockPyth.updatePrice(NvidiaAssetId, int64(2e7), int32(0)); // Use NvidiaAssetId to ensure only NVIDIA is affected
    priceUpdate[0] = mockPyth.createPriceFeedUpdateData(
        NvidiaAssetId,
        int64(2e7),
        uint64(1e7),
        int32(0),
        int64(2e7),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );

    // Investor performs full liquidation
    vm.startPrank(investor);
    lzybravault.liquidation(
        investor,
        userB,
        BORROW_AMOUNT,
        Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(asset1), // NVIDIA asset
            amount: COLLATERAL_AMOUNT,
            tokenId: 0,
            assetPrice: AssetPrice(address(mockPyth), 0, 0)
        }),
        priceUpdate
    );

    uint256 remainingDebt = lzybravault.getBorrowed(userB, address(asset1));
    assertEq(
        remainingDebt,
        0,
        "User debt should be zero after full liquidation"
    );

    uint256 finalInvestorBalance = USDC.balanceOf(investor);
    assertGt(
        finalInvestorBalance,
        initialInvestorBalance,
        "Investor should receive collateral after full liquidation"
    );

    vm.stopPrank();
}

function testLiquidationAfterPartialRepayment() public {
    // Configure assets and offer
    (
        Asset memory withdrawalAsset,
        DotcOffer memory offer
    ) = setupWithdrawalAssetAndOffer(
            address(asset1), // deposit asset (NVIDIA)
            500 * 10 ** 18, // deposit amount
            address(asset2), // withdrawal asset (MICROSOFT)
            1000 * 10 ** 18, // withdrawal amount
            2 * 10 ** 18, // unit price
            1 days, // expiry duration
            1 hours // timelock duration
        );

    // Generate initial price update data for NVIDIA asset
    bytes memory priceUpdateData = mockPyth.createPriceFeedUpdateData(
        NvidiaAssetId,
        int64(1e8),
        uint64(1e7),
        int32(0),
        int64(1e8),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );
    bytes;
    priceUpdate[0] = priceUpdateData;

    // Step 1: User A deposits collateral and creates an offer
    vm.startPrank(userA);
    USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
    lzybravault.deposit(COLLATERAL_AMOUNT, withdrawalAsset, offer);
    vm.stopPrank();

    // Step 2: User B takes the offer and borrows
    vm.startPrank(userB);
    lzybravault.deposit(
        COLLATERAL_AMOUNT,
        nvidiaOfferId, // Offer ID placeholder
        BORROW_AMOUNT,
        true,
        105e18
    );
    vm.stopPrank();

    // Step 3: Partial debt repayment by User B
    uint256 partialRepayment = BORROW_AMOUNT / 2;
    vm.startPrank(userB);
    lzybravault.repayingDebt(
        userB,
        address(asset1),
        partialRepayment,
        priceUpdate
    );
    vm.stopPrank();

    // Step 4: Simulate a price drop to trigger liquidation condition for NVIDIA asset
    mockPyth.updatePrice(NvidiaAssetId, int64(2e7), int32(0)); // Ensure only NVIDIA is affected
    priceUpdate[0] = mockPyth.createPriceFeedUpdateData(
        NvidiaAssetId,
        int64(2e7),
        uint64(1e7),
        int32(0),
        int64(2e7),
        uint64(1e7),
        uint64(block.timestamp),
        uint64(block.timestamp - 1)
    );

    // Step 5: Liquidator attempts partial liquidation
    vm.startPrank(investor);
    lzybravault.liquidation(
        investor,
        userB,
        BORROW_AMOUNT / 4,
        Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(asset1), // NVIDIA asset
            amount: COLLATERAL_AMOUNT / 2,
            tokenId: 0,
            assetPrice: AssetPrice(address(mockPyth), 0, 0)
        }),
        priceUpdate
    );

    // Verify that debt has been reduced after liquidation
    uint256 remainingDebt = lzybravault.getBorrowed(userB, address(asset1));
    assertEq(
        remainingDebt,
        partialRepayment - (BORROW_AMOUNT / 4),
        "Debt should be reduced by liquidation amount"
    );

    vm.stopPrank();
}


    function testLiquidationWithInsufficientDebt() public {
        // Setup assets and offer
        (
            Asset memory withdrawalAsset,
            DotcOffer memory offer
        ) = setupWithdrawalAssetAndOffer(
                address(asset3), // deposit asset (NVIDIA)
                500 * 10 ** 18, // deposit amount
                address(asset2), // withdrawal asset (MICROSOFT)
                1000 * 10 ** 18, // withdrawal amount
                2 * 10 ** 18, // unit price
                1 days, // expiry duration
                1 hours // timelock duration
            );

        // Generate price update data
        bytes memory priceUpdateData = mockPyth.createPriceFeedUpdateData(
            TeslaAssetId,
            int64(1e8),
            uint64(1e7),
            int32(0),
            int64(1e8),
            uint64(1e7),
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        bytes[] memory priceUpdate = new bytes[](1);
        priceUpdate[0] = priceUpdateData;

        // Step 1: User A deposits collateral and creates an offer
        vm.startPrank(userA);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, withdrawalAsset, offer);
        vm.stopPrank();

        // Step 2: User B takes the offer and borrows
        vm.startPrank(userB);
        lzybravault.deposit(
            COLLATERAL_AMOUNT,
            teslaOfferId, // Offer ID placeholder
            BORROW_AMOUNT,
            true,
            105e18
        );
        vm.stopPrank();

        // Partially repay the debt to an amount below the liquidation threshold
        uint256 repaymentAmount = BORROW_AMOUNT - (BORROW_AMOUNT / 4);
        vm.startPrank(userB);
        lzybravault.repayingDebt(
            userB,
            address(asset1),
            repaymentAmount,
            priceUpdate
        );
        vm.stopPrank();

        // Step 3: Attempt liquidation, which should fail due to insufficient debt
        vm.startPrank(investor);
        vm.expectRevert("Debt amount insufficient for liquidation");
        lzybravault.liquidation(
            investor,
            userB,
            BORROW_AMOUNT / 2,
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(asset1),
                amount: BORROW_AMOUNT / 2,
                tokenId: 0,
                assetPrice: AssetPrice(address(mockPyth), 0, 0)
            }),
            priceUpdate
        );

        vm.stopPrank();
    }

    function testLiquidationAfterPartialRepayment() public {
        // Configure assets and offer
        (
            Asset memory withdrawalAsset,
            DotcOffer memory offer
        ) = setupWithdrawalAssetAndOffer(
                address(asset1), // deposit asset (NVIDIA)
                500 * 10 ** 18, // deposit amount
                address(asset2), // withdrawal asset (MICROSOFT)
                1000 * 10 ** 18, // withdrawal amount
                2 * 10 ** 18, // unit price
                1 days, // expiry duration
                1 hours // timelock duration
            );

        // Generate initial price update data
        bytes memory priceUpdateData = mockPyth.createPriceFeedUpdateData(
            NvidiaAssetId,
            int64(1e8),
            uint64(1e7),
            int32(0),
            int64(1e8),
            uint64(1e7),
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        bytes;
        priceUpdate[0] = priceUpdateData;

        // Step 1: User A deposits collateral and creates an offer
        vm.startPrank(userA);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, withdrawalAsset, offer);
        vm.stopPrank();

        // Step 2: User B takes the offer and borrows
        vm.startPrank(userB);
        lzybravault.deposit(
            COLLATERAL_AMOUNT,
            1, // Offer ID placeholder
            BORROW_AMOUNT,
            true,
            105e18
        );
        vm.stopPrank();

        // Step 3: Partial debt repayment by User B
        uint256 partialRepayment = BORROW_AMOUNT / 2;
        vm.startPrank(userB);
        lzybravault.repayingDebt(
            userB,
            address(asset1),
            partialRepayment,
            priceUpdate
        );
        vm.stopPrank();

        // Step 4: Simulate a price drop to trigger liquidation condition
        mockPyth.updatePrice(NvidiaAssetId, int64(2e7), int32(0)); // Simulate severe price drop
        priceUpdate[0] = mockPyth.createPriceFeedUpdateData(
            NvidiaAssetId,
            int64(2e7),
            uint64(1e7),
            int32(0),
            int64(2e7),
            uint64(1e7),
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );

        // Step 5: Liquidator attempts partial liquidation
        vm.startPrank(investor);
        lzybravault.liquidation(
            investor,
            userB,
            BORROW_AMOUNT / 4,
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(asset1),
                amount: COLLATERAL_AMOUNT / 2,
                tokenId: 0,
                assetPrice: AssetPrice(address(mockPyth), 0, 0)
            }),
            priceUpdate
        );

        // Verify that debt has been reduced after liquidation
        uint256 remainingDebt = lzybravault.getBorrowed(userB, address(asset1));
        assertEq(
            remainingDebt,
            partialRepayment - (BORROW_AMOUNT / 4),
            "Debt should be reduced by liquidation amount"
        );

        vm.stopPrank();
    }

    function testExactDebtRepayment() public {
        // Configure assets and offer
        (
            Asset memory withdrawalAsset,
            DotcOffer memory offer
        ) = setupWithdrawalAssetAndOffer(
                address(asset1), // deposit asset (NVIDIA)
                500 * 10 ** 18, // deposit amount
                address(asset3), // withdrawal asset (TESLA)
                1000 * 10 ** 18, // withdrawal amount
                2 * 10 ** 18, // unit price
                1 days, // expiry duration
                1 hours // timelock duration
            );

        // Generate price update data
        bytes memory priceUpdateData = mockPyth.createPriceFeedUpdateData(
            NvidiaAssetId,
            int64(1e8),
            uint64(1e7),
            int32(0),
            int64(1e8),
            uint64(1e7),
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        bytes;
        priceUpdate[0] = priceUpdateData;

        // Step 1: User A deposits collateral and creates an offer
        vm.startPrank(userA);
        USDC.approve(address(lzybravault), COLLATERAL_AMOUNT);
        lzybravault.deposit(COLLATERAL_AMOUNT, withdrawalAsset, offer);
        vm.stopPrank();

        // Step 2: User B takes the offer and borrows
        vm.startPrank(userB);
        lzybravault.deposit(
            COLLATERAL_AMOUNT,
            1, // Offer ID placeholder
            BORROW_AMOUNT,
            true,
            105e18
        );

        // Step 3: Repay exactly the borrowed amount by User B
        lzybravault.repayingDebt(
            userB,
            address(asset1),
            BORROW_AMOUNT,
            priceUpdate
        );

        // Verify that the debt is exactly cleared
        uint256 remainingDebt = lzybravault.getBorrowed(userB, address(asset1));
        assertEq(
            remainingDebt,
            0,
            "Debt should be exactly zero after full repayment"
        );

        vm.stopPrank();
    }
}
