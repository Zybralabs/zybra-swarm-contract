// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;
import "forge-std/console2.sol";

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "./interfaces/AggregatorV2V3Interface.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AssetHelper} from "./helpers/AssetHelper.sol";
import {Asset, AssetType, AssetPrice, OfferStruct, OfferPrice, DotcOffer, OfferFillType} from "./structures/DotcStructuresV2.sol";
import {SafeTransferLib, FixedPointMathLib} from "./exports/ExternalExports.sol";
import {OfferHelper} from "./helpers/OfferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {TokenDecimalUtils} from"./libraries/TokenDecimalUtils.sol";


contract ZybraVault is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;
    using TokenDecimalUtils for uint256;

    /// @dev Used for precise calculations.
    using FixedPointMathLib for uint256;
    /// @dev Used for Asset interaction.
    using AssetHelper for Asset;

    /// @dev Used for Offer interaction.
    using OfferHelper for OfferStruct;
    /// @dev Used for Dotc Offer interaction.

    ILZYBRA public lzybra;
    Iconfigurator public configurator;
    IDotcV2 public dotv2;
    IPyth public pyth;
    AggregatorV2V3Interface internal _priceFeed;
    IERC20 public usdc_collateralAsset;
    uint256 public poolTotalCirculation;

    struct Oracles {
        address chainlink;
        bytes32 pyth;
    }

    mapping(address => mapping(address => uint256)) public userAssets; // User withdraw request stock asset amount
    mapping(address => mapping(address => uint256)) public borrowed;
    mapping(uint256 => uint256) public depositAmounts;
    mapping(uint256 => uint256) public WithdrawalAssetAmount;
    mapping(address => uint256) public feeStored;
    mapping(address => uint256) _feeUpdatedAt;
    mapping(address => Oracles) public assetOracles;

    // Existing events
    event DepositAsset(
        address indexed onBehalfOf,
        address asset,
        uint256 amount
    );

    event CancelDepositRequest(address indexed onBehalfOf, address asset);

    event WithdrawAsset(address indexed sponsor, address asset, uint256 amount);

    event LiquidationRecord(
        address indexed provider,
        address indexed keeper,
        address indexed onBehalfOf,
        uint256 LiquidateAssetAmount,
        uint256 keeperReward
    );

    event OfferClaimed(
        address indexed caller,
        uint256 offerId,
        address asset,
        uint256 amount
    );

    event repayDebt(
        address indexed sender,
        address indexed provider,
        address indexed asset,
        uint256 amount
    );

    // Add new events for specific offer actions
    event MakeWithdraw(address indexed sender, address asset, uint256 amount);

    event DepositOfferClaimed(
        address indexed caller,
        uint256 offerId,
        address indexed purchasedAsset,
        uint256 amount
    );

    event WithdrawOfferClaimed(
        address indexed caller,
        uint256 offerId,
        address indexed soldAsset,
        uint256 amount
    );

    event OfferCancelled(
        address indexed caller,
        uint256 offerId,
        uint256 depositAmount
    );

    modifier onlyExistingAsset(address _asset) {
        Oracles memory oracles = assetOracles[_asset];
        require(
            oracles.chainlink != address(0) || oracles.pyth != bytes32(0),
            "ANO."
        );
        _;
    }

    constructor(
        address _collateralAsset,
        address _lzybra,
        address _dotcv2,
        address _configurator,
        address _usdc_Price_feed,
        bytes32 pyth_Price_feed,
        address _pythAddress
    ) Ownable(msg.sender) {
        // Initialize state variables
        require(_collateralAsset != address(0), "Zero collateral address");
        require(_lzybra != address(0), "Zero LZYBRA address");
        usdc_collateralAsset = IERC20(_collateralAsset);
        lzybra = ILZYBRA(_lzybra);
        dotv2 = IDotcV2(_dotcv2);
        configurator = Iconfigurator(_configurator);
        assetOracles[_collateralAsset] = Oracles({
            chainlink: _usdc_Price_feed,
            pyth: pyth_Price_feed
        });
        pyth = IPyth(_pythAddress);

        // Initialize mappings as needed
        poolTotalCirculation = 0; // Defaults to 0, but explicitly set for clarity

        // Initialize fees and other mappings
        // Set default timestamps and fee storage
        // _feeUpdatedAt and feeStored mappings will start with zero values
    }

    /**
     * @notice Deposit USDC, update the interest distribution, can mint LZybra directly
     * Emits a `DepositAsset` event.
     *
     * Requirements:
     * - `assetAmount` Must be higher than 0.
     * - `withdrawalAsset` withdrawal Asset details in Asset struct
     * - `offer` offers details in OfferStruct struct
     */
    function deposit(
        uint256 assetAmount,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer,
        uint256 mintAmount
    )
        external
        virtual
        onlyExistingAsset(withdrawalAsset.assetAddress)
        nonReentrant
    {
        require(assetAmount > 0, "ZA");

        // Transfer collateral to the contract
        usdc_collateralAsset.transferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        // Approve DOTC contract only if needed
        _approveIfNeeded(
            address(usdc_collateralAsset),
            address(dotv2),
            assetAmount
        );

        // Create an Asset struct for the deposit
        Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(usdc_collateralAsset),
            amount: assetAmount,
            tokenId: 0,
            assetPrice: AssetPrice(
                assetOracles[address(usdc_collateralAsset)].chainlink,
                0,
                0
            )
        });

        // Create the offer in dotv2
        dotv2.makeOffer(usdc_asset, withdrawalAsset, offer);
        uint256 offerId = dotv2.currentOfferId();
        depositAmounts[offerId] = assetAmount;
        WithdrawalAssetAmount[offerId] = withdrawalAsset.amount;
        userAssets[msg.sender][usdc_asset.assetAddress] += assetAmount;
        uint256 depositToWithdrawalRate = _getFallbackPrice(
            address(usdc_collateralAsset)
        );
        // uint256  depositToWithdrawalRate = 1e18;
        // Mint lzybra tokens based on the asset price and deposit amount
        _mintLZYBRA(
            msg.sender,
            mintAmount,
            depositToWithdrawalRate,
            usdc_asset.assetAddress
        );

        // Emit the DepositAsset event after state changes
        emit DepositAsset(
            msg.sender,
            address(usdc_collateralAsset),
            assetAmount
        );
    }

    /**
     * @notice Deposit USDC for an existing offer and mint LZYBRA tokens
     * @param assetAmount Amount of USDC to deposit
     * @param offerId ID of the offer to take
     * @param mintAmount Amount of LZYBRA tokens to mint
     * @param isDynamic Whether to use dynamic or fixed pricing
     * @param maximumDepositToWithdrawalRate Maximum acceptable rate for dynamic pricing
     * @dev Handles both fixed and dynamic pricing while ensuring proper accounting
     */
    function depositWithOfferId(
        uint256 assetAmount,
        uint256 offerId,
        uint256 mintAmount,
        bool isDynamic,
        uint256 maximumDepositToWithdrawalRate
    ) external virtual nonReentrant {
        // Input validation
        require(assetAmount > 0, "Zero amount not allowed");
        require(offerId > 0, "Invalid offer ID");

        // Get offer details from DotcV2
        (
            address maker,
            OfferFillType offerFillType,
            Asset memory depositAsset,
            Asset memory withdrawalAsset,
            OfferStruct memory offerDetails
        ) = dotv2.allOffers(offerId);

        // Validate offer
        require(maker != address(0), "Offer does not exist");
        require(offerFillType != OfferFillType.Cancelled, "Offer is cancelled");
        require(
            offerFillType != OfferFillType.FullyTaken,
            "Offer is fully taken"
        );

        // Validate asset types
        require(
            withdrawalAsset.assetAddress == address(usdc_collateralAsset),
            "Withdrawal asset must be USDC"
        );

        // Ensure the deposit asset has oracle price feeds
        Oracles memory assetOracle = assetOracles[depositAsset.assetAddress];
        require(
            assetOracle.chainlink != address(0) ||
                assetOracle.pyth != bytes32(0),
            "Asset requires oracle price feed"
        );

        // Calculate expected exchange rate before asset transfer
        (uint256 depositToWithdrawalRate, uint256 withdrawalPrice) = AssetHelper
            .getRateAndPrice(
                depositAsset,
                withdrawalAsset,
                offerDetails.offerPrice
            );

        // Validate price limit for dynamic pricing
        if (isDynamic && maximumDepositToWithdrawalRate > 0) {
            require(
                depositToWithdrawalRate <= maximumDepositToWithdrawalRate,
                "Rate exceeds maximum limit"
            );
        }

        // Transfer USDC from user to contract
        bool transferSuccess = usdc_collateralAsset.transferFrom(
            msg.sender,
            address(this),
            assetAmount
        );
        require(transferSuccess, "USDC transfer failed");

        // Approve DOTC contract to use our USDC
        _approveIfNeeded(
            address(usdc_collateralAsset),
            address(dotv2),
            assetAmount
        );

        uint256 receivedWithdrawalAmount;

        // Take the offer based on pricing type
        if (isDynamic) {
            // Save initial deposit asset amount
            uint256 initialDepositAmount = depositAsset.amount;

            // Take dynamic offer
            dotv2.takeOfferDynamic(
                offerId,
                assetAmount,
                maximumDepositToWithdrawalRate > 0
                    ? maximumDepositToWithdrawalRate
                    : depositToWithdrawalRate,
                address(this)
            );

            // Get updated offer state
            (, , Asset memory newDepositAsset, , ) = dotv2.allOffers(offerId);

            // Calculate received amount based on asset change
            if (newDepositAsset.amount > initialDepositAmount) {
                receivedWithdrawalAmount =
                    newDepositAsset.amount -
                    initialDepositAmount;
            } else {
                // Handle case where amount decreased (shouldn't happen normally)
                revert("Invalid post-offer asset state");
            }
        } else {
            // Take fixed offer
            dotv2.takeOfferFixed(offerId, assetAmount, address(this));

            // Calculate received withdrawal amount for fixed rate
            uint256 scaledRate = TokenDecimalUtils.convertDecimals(
                depositToWithdrawalRate,
                8,
                18
            );
            uint256 assetDecimals = 10 **
                IERC20(depositAsset.assetAddress).decimals();

            // Use fullMulDiv for precise calculation without overflow
            receivedWithdrawalAmount = assetAmount.fullMulDiv(
                scaledRate,
                assetDecimals
            );

            // Validate result
            require(receivedWithdrawalAmount > 0, "Zero received amount");
        }

        // Update user asset balance
        userAssets[msg.sender][
            depositAsset.assetAddress
        ] += receivedWithdrawalAmount;

        // Convert rate to 18 decimals for minting calculation
        uint256 normalizedRate = TokenDecimalUtils.convertDecimals(
            depositToWithdrawalRate,
            8,
            18
        );

        // Validate mint amount if provided
        if (mintAmount > 0) {
            // Mint LZYBRA tokens
            _mintLZYBRA(
                msg.sender,
                mintAmount,
                normalizedRate,
                depositAsset.assetAddress
            );
        }

        // Emit deposit event with details
        emit DepositAsset(
            msg.sender,
            depositAsset.assetAddress,
            receivedWithdrawalAmount
        );
    }

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawAsset` event.
     *
     * Requirements:
     * - `offerId` cannot be the zero address.
     * - `asset_amount` Must be higher than 0.
     
     * @dev Withdraw collateral. Check user’s collateral ratio after withdrawal, should be higher than `safeCollateralRatio`
     */

    function withdraw(
        uint256 assetAmount,
        Asset calldata depositAsset,
        OfferStruct calldata offer
    ) external virtual nonReentrant {
        require(assetAmount > 0, "ZA");
        // Transfer collateral to the contract
        uint256 userAsset = userAssets[msg.sender][depositAsset.assetAddress];
        // Ensure user has enough assets to withdraw
        require(userAsset >= assetAmount, "AX");

        _approveIfNeeded(
            address(depositAsset.assetAddress),
            address(dotv2),
            assetAmount
        );

        // Create an Asset struct for the deposit
        Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(usdc_collateralAsset),
            amount: assetAmount,
            tokenId: 0,
            assetPrice: AssetPrice(
                assetOracles[address(usdc_collateralAsset)].chainlink,
                0,
                0
            )
        });

        // Create the offer in dotv2
        dotv2.makeOffer(depositAsset, usdc_asset, offer);
        uint256 offerId = dotv2.currentOfferId();
        WithdrawalAssetAmount[offerId] = assetAmount;
        depositAmounts[offerId] = depositAsset.amount;

        // Emit withdrawal event with net amount received
        emit MakeWithdraw(msg.sender, depositAsset.assetAddress, assetAmount);
    }

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawAsset` event.
     *
     * Requirements:
     * - `offerId` cannot be the zero address.
     * - `asset_amount` Must be higher than 0.
     
     * @dev Withdraw collateral. Check user’s collateral ratio after withdrawal, should be higher than `safeCollateralRatio`
     */

    function withdrawWithOfferId(
        uint256 offerId,
        uint256 assetAmount,
        uint256 burnAmount,
        uint256 maximumDepositToWithdrawalRate,
        bool isDynamic
    ) external virtual nonReentrant {
        require(assetAmount > 0, "ZA");

        // Get the offer and destructure it properly
        (
            ,
            ,
            Asset memory depositAsset,
            Asset memory withdrawalAsset,
            OfferStruct memory offerDetails
        ) = dotv2.allOffers(offerId);

        address depositAssetAddr = depositAsset.assetAddress;
        uint256 userAsset = userAssets[msg.sender][depositAssetAddr];

        // Ensure user has enough assets to withdraw
        require(userAsset >= assetAmount, "AX.");
        require(depositAssetAddr == address(usdc_collateralAsset), "AA.");

        // Approve DOTC contract only if needed
        _approveIfNeeded(depositAssetAddr, address(dotv2), assetAmount);

        (uint256 assetRate, ) = AssetHelper.getRateAndPrice(
            depositAsset,
            withdrawalAsset,
            offerDetails.offerPrice
        );

        // Check health only if there are borrowed assets
        if (getBorrowed(msg.sender, depositAssetAddr) > 0) {
            _checkHealth(msg.sender, depositAssetAddr, assetRate);
        }

        uint256 receivingAmount;
        if (isDynamic) {
            // Dynamic Offer Withdrawal
            dotv2.takeOfferDynamic(
                offerId,
                assetAmount,
                maximumDepositToWithdrawalRate,
                msg.sender
            );

            // Get updated offer state
            (, , Asset memory newDepositAsset, , ) = dotv2.allOffers(offerId);
            receivingAmount = depositAsset.amount - newDepositAsset.amount;
        } else {
            // Fixed Offer Withdrawal
            dotv2.takeOfferFixed(offerId, assetAmount, msg.sender);
            receivingAmount = assetAmount != withdrawalAsset.amount
                ? depositAsset.unstandardize(
                    withdrawalAsset.standardize(assetAmount).fullMulDiv(
                        AssetHelper.BPS,
                        offerDetails.offerPrice.unitPrice
                    )
                )
                : depositAsset.amount;
        }

        // Calculate and subtract fees, ensuring valid amount is received
        uint256 fee = feeStored[msg.sender];
        require(receivingAmount > fee, "TZA");
        receivingAmount -= fee;

        // Calculate and repay lzybra based on user's share
        _repay(msg.sender, msg.sender, depositAssetAddr, burnAmount);

        // Update user balance in storage
        unchecked {
            userAssets[msg.sender][depositAssetAddr] = userAsset - assetAmount;
        }

        // Transfer remaining collateral after fee deduction
        usdc_collateralAsset.transfer(msg.sender, receivingAmount);

        // Emit withdrawal event with net amount received
        emit WithdrawAsset(msg.sender, depositAssetAddr, receivingAmount);
    }

    /**
     * @notice Keeper liquidates borrowers whose collateral ratio is below badCollateralRatio, using lzybra provided by Liquidation Provider.
     *
     * Requirements:
     * - provider should authorize Zybra to utilize lzybra
     * - onBehalfOf Collateral Ratio should be below badCollateralRatio
     * - assetAmount should be less than 50% of collateral
     * - asset Asset to be Liquidated
     * - priceUpdate priceUpdate comes from Hermes Api to get token price from Pyth Oracle  
     
     * @dev After liquidation, borrower's debt is reduced by assetAmount * AssetPrice, providers and keepers can receive up to an additional 10% liquidation reward.
     */

   function liquidation(
    address provider,
    address onBehalfOf,
    uint256 assetAmount,
    Asset calldata asset,
    bytes[] calldata priceUpdate
) external payable nonReentrant {
    // Input Validation
    require(asset.assetAddress != address(0), "IA");
    require(assetAmount > 0, "AG");
    require(onBehalfOf != address(0), "IB");
    require(provider != address(0), "IP");

    // Fetch collateral ratio and validate liquidation threshold
    address tAddress = asset.assetAddress;
    
    (
        bool shouldLiquidate,
        uint256 collateralRatio,
        uint256 assetPrice
    ) = getCollateralRatioAndLiquidationInfo(
            onBehalfOf,
            tAddress,
            priceUpdate
        );
    require(shouldLiquidate, "AL");

    // Ensure liquidation amount does not exceed 50% of collateral (in native token decimals)
    require(assetAmount * 2 <= userAssets[onBehalfOf][tAddress], "MC5");

    // Authorization Check
    require(
        msg.sender == provider ||
            lzybra.allowance(provider, address(this)) >= assetAmount,
        "PMA"
    );

    // For calculation with price (which is in 18 decimals), we normalize the asset amount
    uint256 assetDecimals = IERC20(tAddress).decimals();
    uint256 normalizedAssetAmount = TokenDecimalUtils.normalizeToDecimals18(
        assetAmount,
        tAddress,
        assetDecimals
    );
    
    // Calculate Lzybra amount with normalized values
    uint256 lzybraAmount = normalizedAssetAmount.fullMulDiv(assetPrice, 1e18);

    // Initialize variables - keep in native decimals for transfers
    uint256 keeperReward = 0;
    uint256 reducedAsset = assetAmount;

    // Adjust reducedAsset and calculate keeper reward if collateral ratio is above threshold
    if (collateralRatio > 1e20) {
        reducedAsset = (collateralRatio < 11e19)
            ? (assetAmount * collateralRatio) / 1e20
            : (assetAmount * 11) / 10;

        // Calculate keeper reward if applicable
        uint256 keeperRatio = configurator.vaultKeeperRatio(address(this));
        if (
            msg.sender != provider &&
            collateralRatio >= 1e20 + keeperRatio * 1e18
        ) {
            keeperReward = assetAmount.fullMulDiv(keeperRatio, 100);
            require(keeperReward <= reducedAsset, "KRD");

            // Transfer keeper reward (using native decimals)
            IERC20(tAddress).transfer(msg.sender, keeperReward);
        }
    }

    // Repay debt using calculated lzybra amount (in 18 decimals)
    _repay(provider, onBehalfOf, tAddress, lzybraAmount);

    // Transfer remaining assets to provider (in native decimals)
    uint256 providerAmount = reducedAsset - keeperReward;
    IERC20(tAddress).transfer(provider, providerAmount);

    // Adjust userAsset storage in a single update (in native decimals)
    userAssets[onBehalfOf][tAddress] -= (reducedAsset + keeperReward);

    // Emit events for critical actions
    emit LiquidationRecord(
        provider,
        msg.sender,
        onBehalfOf,
        lzybraAmount,
        reducedAsset
    );
}

    function repayingDebt(
        address provider,
        address asset,
        uint256 lzybraAmount,
        bytes[] calldata priceUpdate
    ) external payable virtual {
        require(borrowed[asset][provider] >= lzybraAmount, "LSD");
        (
            ,
            uint256 providerCollateralRatio,

        ) = getCollateralRatioAndLiquidationInfo(provider, asset, priceUpdate);

        // Ensure the collateral ratio is healthy (at least 100%) for debt repayment
        require(
            providerCollateralRatio >=
                configurator.getSafeCollateralRatio(address(this))
        );
        _repay(provider, asset, provider, lzybraAmount);
        emit repayDebt(msg.sender, provider, asset, lzybraAmount);
    }

    /**
     * @notice Claims an offer that has been fully taken
     * @param offerId The ID of the offer to claim
     * @param lzybraDebt The amount of LZYBRA debt to repay when claiming the offer
     * @param priceUpdate Price update data for oracle price verification
     * @dev Follows checks-effects-interactions pattern to prevent reentrancy
     */
 function claimOffer(
    uint256 offerId,
    uint256 lzybraDebt,
    bytes[] calldata priceUpdate
) external nonReentrant {
    address caller = msg.sender;
    address usdcAddress = address(usdc_collateralAsset);
    
    // Get the offer and destructure it properly
    (
        address maker,
        OfferFillType offerFillType,
        Asset memory depositAsset,
        Asset memory withdrawalAsset,
    ) = dotv2.allOffers(offerId);

    // Verify offer validity with a single require for gas optimization
    require(
        maker != address(0) && 
        maker == address(this) && 
        offerFillType == OfferFillType.FullyTaken,
        "IFS"
    );

    // Store values in memory and immediately clear storage to prevent reentrancy
    uint256 amount = WithdrawalAssetAmount[offerId];
    uint256 originalDepositAmount = depositAmounts[offerId];
    
    // Validate amounts before clearing storage
    require(amount > 0 && originalDepositAmount > 0, "IA");
    
    // Clear storage immediately (CEI pattern)
    WithdrawalAssetAmount[offerId] = 0;
    depositAmounts[offerId] = 0;

    bool isDeposit = depositAsset.assetAddress == usdcAddress;

    if (isDeposit) {
        // USDC -> Other Asset flow
        address purchasedAsset = withdrawalAsset.assetAddress;
        require(purchasedAsset != address(0), "ZAA");

        uint256 totalUserUSDC = userAssets[caller][usdcAddress];
        require(totalUserUSDC >= originalDepositAmount, "IUB");

        // Calculate debt share using FixedPointMathLib for precision
        uint256 currentDebt = borrowed[caller][usdcAddress];
        uint256 offerDebtShare = 0;
        
        if (currentDebt > 0) {
            offerDebtShare = currentDebt.fullMulDiv(
                originalDepositAmount,
                totalUserUSDC
            );
            
            // Ensure we don't move more debt than exists
            require(offerDebtShare <= currentDebt, "EDS");
            
            // Update debt records
            borrowed[caller][purchasedAsset] += offerDebtShare;
            borrowed[caller][usdcAddress] = currentDebt - offerDebtShare;
        }

        // Update state variables
        userAssets[caller][usdcAddress] = totalUserUSDC - originalDepositAmount;
        userAssets[caller][purchasedAsset] += amount;

        // Update fee state after state changes
        _updateFee(caller, purchasedAsset);

        // Emit event last (after all state changes)
        emit DepositOfferClaimed(
            caller,
            offerId,
            purchasedAsset,
            amount
        );
    } else {
        // Other Asset -> USDC flow
        address soldAsset = depositAsset.assetAddress;
        require(soldAsset != address(0), "ZAS");

        // Require user has sufficient balance
        require(userAssets[caller][soldAsset] >= amount, "IAB");

        // Update state before external calls
        userAssets[caller][soldAsset] -= amount;

        // Handle debt repayment if applicable
        if (lzybraDebt > 0) {
            require(lzybraDebt <= borrowed[caller][soldAsset], "DEB");
            
            // Get oracle price before repayment for health check
            uint256 assetPrice = 0;
            if (borrowed[caller][soldAsset] - lzybraDebt > 0) {
                assetPrice = _getFallbackPrice(soldAsset);
            }
            
            // Repay debt
            _repay(caller, caller, soldAsset, lzybraDebt);
            
            // Verify position health after repayment
            if (borrowed[caller][soldAsset] > 0) {
                _checkHealth(caller, soldAsset, assetPrice);
            }
        } else if (borrowed[caller][soldAsset] > 0) {
            // If not repaying but debt exists, verify health
            uint256 assetPrice = _getFallbackPrice(soldAsset);
            _checkHealth(caller, soldAsset, assetPrice);
        }

        // Transfer assets after state updates and health checks
        require(
            usdc_collateralAsset.transfer(caller, amount),
            "UTF"
        );

        // Emit event
        emit WithdrawOfferClaimed(caller, offerId, soldAsset, amount);
    }
}

    /**
     * @notice Cancels an existing offer and returns assets to the offer creator
     * @param offerId The ID of the offer to cancel
     * @param lzybraDebt The amount of LZYBRA debt to repay when canceling
     * @dev Follows checks-effects-interactions pattern to prevent reentrancy
     */
 function cancelOffer(
    uint256 offerId,
    uint256 lzybraDebt
) external nonReentrant {
    address caller = msg.sender;
    address usdcAddress = address(usdc_collateralAsset);
    
    // Get the offer and destructure it properly
    (
        address maker,
        OfferFillType offerFillType,
        Asset memory depositAsset,
        Asset memory withdrawalAsset,
    ) = dotv2.allOffers(offerId);

    // Verify offer validity with consolidated require
    require(
        maker != address(0) && 
        maker == address(this) && 
        offerFillType != OfferFillType.FullyTaken && 
        offerFillType != OfferFillType.Cancelled,
        "IFS"
    );

    // Load deposit amount and check validity before clearing storage
    uint256 depositAmount = depositAmounts[offerId];
    require(depositAmount > 0, "IDA");
    
    // Store withdrawal amount for event emission
    uint256 withdrawalAmount = WithdrawalAssetAmount[offerId];
    
    // Clear storage immediately (CEI pattern)
    depositAmounts[offerId] = 0;
    WithdrawalAssetAmount[offerId] = 0;

    // Store relevant data in memory
    bool isDeposit = depositAsset.assetAddress == usdcAddress;
    address assetAddress = isDeposit ? usdcAddress : withdrawalAsset.assetAddress;
    
    // Ensure asset address is valid
    require(assetAddress != address(0), "ZAA");
    
    // Verify user has sufficient balance
    require(userAssets[caller][assetAddress] >= depositAmount, "IUB");
    
    // Update user assets state
    userAssets[caller][assetAddress] -= depositAmount;

    // Cancel offer in DOTCV2 first to prevent reentrancy concerns
    dotv2.cancelOffer(offerId);

    // Handle debt repayment if applicable
    if (isDeposit && lzybraDebt > 0) {
        uint256 currentDebt = borrowed[caller][usdcAddress];
        require(currentDebt >= lzybraDebt, "DEB");
        
        // Get price if needed for health check after repayment
        uint256 assetPrice = 0;
        if (currentDebt > lzybraDebt) {
            assetPrice = _getFallbackPrice(usdcAddress);
        }
        
        // Repay debt
        _repay(caller, caller, usdcAddress, lzybraDebt);
        
        // Check health if there's remaining debt
        if (borrowed[caller][usdcAddress] > 0) {
            _checkHealth(caller, usdcAddress, assetPrice);
        }
    }

    // Calculate fee if applicable
    uint256 fee = isDeposit ? feeStored[caller] : 0;
    
    // Calculate return amount
    uint256 amountToReturn = depositAmount;
    if (isDeposit && fee > 0) {
        amountToReturn = depositAmount > fee ? depositAmount - fee : 0;
        
        // If fee is being collected, update fee storage
        if (amountToReturn < depositAmount) {
            // Only deduct the fee actually taken
            feeStored[caller] -= (depositAmount - amountToReturn);
        }
    }
    
    // Transfer assets back to caller with proper error handling
    bool transferSuccess;
    if (isDeposit) {
        transferSuccess = usdc_collateralAsset.transfer(caller, amountToReturn);
        require(transferSuccess, "UTF");
    } else {
        transferSuccess = IERC20(assetAddress).transfer(caller, amountToReturn);
        require(transferSuccess, "ATF");
    }

    // Emit event after all operations are complete
    emit OfferCancelled(caller, offerId, depositAmount);
}

    /**
     * @dev Refresh LBR reward before adding providers debt. Refresh Zybra generated service fee before adding totalSupply. Check providers collateralRatio cannot below `safeCollateralRatio`after minting.
     */
    function _mintLZYBRA(
        address _provider,
        uint256 _mintAmount,
        uint256 _assetPrice,
        address asset
    ) internal virtual {
        require(
            poolTotalCirculation + _mintAmount <=
                configurator.mintVaultMaxSupply(address(this)),
            "ESL"
        );

        _updateFee(_provider, asset);
        borrowed[_provider][asset] += _mintAmount;
        if (_mintAmount > 0) {
            _checkHealth(_provider, asset, _assetPrice);
        }

        lzybra.mint(_provider, _mintAmount);
        poolTotalCirculation += _mintAmount;
    }

    /**
     * @notice Burn _provideramount lzybra to payback minted lzybra for _onBehalfOf.
     *
     * @dev rePAY the User debt so the Collateral Ratio for user is mantained.
     */
    function _repay(
        address _provider,
        address _onBehalfOf,
        address asset,
        uint256 _amount
    ) internal virtual {
        _updateFee(_onBehalfOf, asset);
        lzybra.transferFrom(_provider, address(this), _amount);
        lzybra.burn(_provider, _amount);
        borrowed[_onBehalfOf][asset] -= _amount;
        poolTotalCirculation -= _amount;
    }

    function setAssetOracles(
        address asset,
        address chainlinkOracle,
        bytes32 pythOracle
    ) external {
        require(
            chainlinkOracle != address(0) || pythOracle != bytes32(0),
            "A1O"
        );

        assetOracles[asset] = Oracles({
            chainlink: chainlinkOracle,
            pyth: pythOracle
        });
    }

    /**
     * @dev Get USD value of current collateral asset and minted lzybra through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
     */
   function _checkHealth(address user, address asset, uint256 price) internal view {
    // Get token decimals
    uint256 assetDecimals = IERC20(asset).decimals();
    
    // Normalize user assets to 18 decimals
    uint256 normalizedUserAssets = TokenDecimalUtils.normalizeToDecimals18(
        userAssets[user][asset],
        asset,
        assetDecimals
    );
    
    // Normalize borrowed amount (though it should already be in 18 decimals)
    uint256 normalizedBorrowed = getBorrowed(user, asset);
    
    // Price is already normalized to 18 decimals
    if (
        (normalizedUserAssets * price * 100) < 
        (normalizedBorrowed * configurator.getSafeCollateralRatio(address(this)))
    ) revert("CBS");
}

  

    function _updateFee(address user, address asset) internal {
        if (block.timestamp > _feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user, asset);
            _feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(
        address user,
        address asset
    ) internal view returns (uint256) {
        uint256 yearlyRate = 100; // 1%
        uint256 dailyRate = yearlyRate.fullMulDiv(1, 365); // Daily rate
        return borrowed[user][asset].fullMulDiv(dailyRate, 10_000); // Apply daily rate
    }
    /**
     * @dev Approve tokens only if allowance is insufficient.
     */
    function _approveIfNeeded(
        address asset,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = IERC20(asset).allowance(
            address(this),
            spender
        );
        if (currentAllowance < amount) {
            bool success = IERC20(asset).approve(
                spender,
                (amount - currentAllowance)
            );
            require(success, "AF");
        }
    }

    /**
     * @dev Returns the current borrowing amount for the user, including borrowed shares and accumulated fees.
     * @param user The address of the user.
     * @return The total borrowing amount for the user.
     */
    function getBorrowed(
        address user,
        address asset
    ) public view returns (uint256) {
        return borrowed[user][asset];
    }

    function getPoolTotalCirculation() external view returns (uint256) {
        return poolTotalCirculation;
    }

    function _calcShare(uint256 amount, address asset, address user) internal view returns (uint256) {
    uint256 borrowedAmount = borrowed[user][asset];
    uint256 userAssetAmount = userAssets[user][asset];
    require(userAssetAmount > 0, "USA");

    // Only normalize for the actual calculation, not for storage
    uint256 assetDecimals = IERC20(asset).decimals();
    
    if (assetDecimals != 18) {
        // Only normalize if the decimals differ from the standard
        uint256 normalizedAmount = TokenDecimalUtils.normalizeToDecimals18(
            amount,
            asset,
            assetDecimals
        );
        uint256 normalizedUserAssetAmount = TokenDecimalUtils.normalizeToDecimals18(
            userAssetAmount,
            asset,
            assetDecimals
        );
        
        return borrowedAmount.fullMulDiv(normalizedAmount, normalizedUserAssetAmount);
    } else {
        // If decimals are already 18, skip normalization
        return borrowedAmount.fullMulDiv(amount, userAssetAmount);
    }
}

    function getCollateralRatioAndLiquidationInfo(
    address user,
    address asset,
    bytes[] calldata priceUpdate
) public returns (
    bool shouldLiquidate,
    uint256 collateralRatio,
    uint256 assetPrice
) {
    // Get the user's asset amount
    uint256 userCollateralAmount = userAssets[user][asset];
    
    // Get asset price (already in 18 decimals)
    assetPrice = getAssetPriceOracle(asset, priceUpdate);

    // Get token decimals
    uint256 assetDecimals = IERC20(asset).decimals();
    
    // Calculate the USD value of the collateral - normalize only for price calculation
    uint256 collateralValueInUSD;
    
    if (assetDecimals != 18) {
        uint256 normalizedCollateralAmount = TokenDecimalUtils.normalizeToDecimals18(
            userCollateralAmount,
            asset,
            assetDecimals
        );
        collateralValueInUSD = (normalizedCollateralAmount * assetPrice) / 1e18;
    } else {
        collateralValueInUSD = (userCollateralAmount * assetPrice) / 1e18;
    }

    // Get the user's total borrowed amount (already in 18 decimals)
    uint256 userDebtAmount = getBorrowed(user, asset);

    // Avoid division by zero
    if (userDebtAmount == 0) {
        return (false, type(uint256).max, assetPrice);
    }

    // Calculate the collateral ratio
    collateralRatio = collateralValueInUSD.fullMulDiv(1e20, userDebtAmount);

    // Determine if collateral ratio is below the liquidation threshold
    uint256 badCollateralRatio = configurator.getBadCollateralRatio(address(this));
    shouldLiquidate = collateralRatio < badCollateralRatio;
}

    function getAssetPriceOracle(
        address _asset,
        bytes[] calldata priceUpdate
    ) public payable returns (uint256) {
        Oracles memory oracles = assetOracles[_asset];

        // Validate that the asset has at least one oracle set
        require(
            oracles.chainlink != address(0) || oracles.pyth != bytes32(0),
            "NPA."
        );

        uint256 fee;

        // Attempt to update the Pyth price feed if a Pyth oracle is set
        if (oracles.pyth != bytes32(0)) {
            // Calculate the fee required to update the price
            fee = pyth.getUpdateFee(priceUpdate);

            // Update the price feeds - Pyth's contract will verify signatures internally
            try pyth.updatePriceFeeds{value: fee}(priceUpdate) {
                // No additional signature check needed since Pyth already performs this
            } catch {
                revert("IPV.");
            }

            int64 priceInt;

            // Attempt to get the primary price feed from Pyth (Pyth returns prices with 8 decimals)
            try pyth.getPriceNoOlderThan(oracles.pyth, 60) returns (
                PythStructs.Price memory priceData
            ) {
                priceInt = priceData.price;
            } catch {
                // If Pyth fails, attempt to get the Chainlink price
                return _getFallbackPrice(_asset);
            }

            // Ensure the price is non-negative
            require(priceInt > 0, "PNN.");

            // Pyth returns prices with 8 decimals, scale to 18 decimals
            uint256 scaledPrice = TokenDecimalUtils.convertDecimals(
                uint256(int256(priceInt)),
                8,
                18
            );

            return scaledPrice; // Return the price in 18 decimals
        }

        // If no Pyth oracle is set, use the Chainlink fallback directly
        return _getFallbackPrice(_asset);
    }

    // Fallback price function for Chainlink (already 8 decimals)
    function _getFallbackPrice(address _asset) internal view returns (uint256) {
        Oracles memory oracles = assetOracles[_asset];

        // Validate that a Chainlink oracle is set for the asset
        require(oracles.chainlink != address(0), "NCA.");

        // Fetch the latest price from Chainlink
        (, int256 price, , uint256 updatedAt, ) = AggregatorV2V3Interface(
            oracles.chainlink
        ).latestRoundData();

        // require(updatedAt > block.timestamp - 86400, "PCO");
        // Ensure the price is non-negative
        require(price >= 0, "CPC.");

        // Chainlink returns prices with 8 decimals, scale to 18 decimals
        return TokenDecimalUtils.convertDecimals(uint256(price), 8, 18);
    }
}
