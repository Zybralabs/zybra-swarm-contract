// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "./interfaces/AggregatorV2V3Interface.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/access/OwnableUpgradeable.sol";
import {AssetHelper} from "./helpers/AssetHelper.sol";
import {Asset, AssetType, AssetPrice, OfferStruct, OfferPrice, DotcOffer} from "./structures/DotcStructuresV2.sol";
import {SafeTransferLib, FixedPointMathLib} from "./exports/ExternalExports.sol";
import {OfferHelper} from "./helpers/OfferHelper.sol";
import {DotcOfferHelper} from "./helpers/DotcOfferHelper.sol";

contract LzybraVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    using SafeTransferLib for address;
    /// @dev Used for precise calculations.
    using FixedPointMathLib for uint256;
    /// @dev Used for Asset interaction.
    using AssetHelper for Asset;

    /// @dev Used for Offer interaction.
    using OfferHelper for OfferStruct;
    /// @dev Used for Dotc Offer interaction.
    using DotcOfferHelper for DotcOffer;

    ILZYBRA public Lzybra;
    address public usdc_price_feed;
    Iconfigurator public configurator;
    IDotcV2 public dotv2;
    IPyth public pyth;
    AggregatorV2V3Interface internal priceFeed;
    IERC20 public collateralAsset;
    uint256 poolTotalCirculation;

    mapping(address => mapping(address => uint256)) public UserAsset; // User withdraw request tranche asset amount
    mapping(address => mapping(address => uint256)) public borrowed;
    mapping(address => uint256) public feeStored;
    mapping(address => uint256) feeUpdatedAt;
    mapping(address => bytes32) public ASSET_ORACLE;

    event DepositAsset(
        address indexed onBehalfOf,
        address asset,
        uint256 amount
    );
    event CancelDepositRequest(address indexed onBehalfOf, address asset);

    event WithdrawAsset(address indexed sponsor, address asset, uint256 amount);
    event Mint(address indexed sponsor, uint256 amount);
    event Burn(
        address indexed sponsor,
        address indexed onBehalfOf,
        uint256 amount
    );
    event LiquidationRecord(
        address indexed provider,
        address indexed keeper,
        address indexed onBehalfOf,
        uint256 LiquidateAssetAmount,
        uint256 keeperReward
    );

    modifier onlyExistingAsset(address _asset) {
        require(
            ASSET_ORACLE[_asset] != bytes32(0),
            "Asset not found in the oracle."
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _collateralAsset,
        address _lzybra,
        address _dotcv2,
        address _configurator,
        address _usdc_price_feed,
        address _pythAddress
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        // Initialize state variables
        collateralAsset = IERC20(_collateralAsset);
        Lzybra = ILZYBRA(_lzybra);
        dotv2 = IDotcV2(_dotcv2);
        configurator = Iconfigurator(_configurator);
        usdc_price_feed = _usdc_price_feed;
        pyth = IPyth(_pythAddress);

        // Initialize mappings as needed
        poolTotalCirculation = 0; // Defaults to 0, but explicitly set for clarity

        // Initialize fees and other mappings
        // Set default timestamps and fee storage
        // feeUpdatedAt and feeStored mappings will start with zero values
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

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
        OfferStruct calldata offer
    )
        external
        virtual
        onlyExistingAsset(withdrawalAsset.assetAddress)
        nonReentrant
    {
        require(assetAmount > 0, "Deposit amount must be greater than 0");

        // Transfer collateral to the contract
        collateralAsset.safeTransferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        // Approve DOTC contract only if needed
        _approveIfNeeded(address(collateralAsset), address(dotv2), assetAmount);

        // Create an Asset struct for the deposit
        Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(collateralAsset),
            amount: assetAmount,
            tokenId: 0,
            assetPrice: AssetPrice(usdc_price_feed, 0, 0)
        });

        // Create the offer in dotv2
        dotv2.makeOffer(usdc_asset, withdrawalAsset, offer);

        UserAsset[msg.sender][usdc_asset.assetAddress] += assetAmount;

        // Mint Lzybra tokens based on the asset price and deposit amount
        _mintLZYBRA(
            msg.sender,
            assetAmount,
            depositToWithdrawalRate,
            usdc_asset.assetAddress
        );

        // Emit the DepositAsset event after state changes
        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount);
    }

    /**
     * @notice Deposit USDC, update the interest distribution, can mint LZybra directly
     * Emits a `DepositAsset` event.
     *
     * Requirements:
     * - `assetAmount` Must be higher than 0.
     * - `offerId` offerId representing the offer to takeOffer
     * - `mintAmount` mint amount of lzybra
     */

    function deposit(
        uint256 assetAmount,
        uint256 offerId,
        uint256 mintAmount,
        bool isDynamic,
        uint256 maximumDepositToWithdrawalRate
    ) external virtual nonReentrant {
        // Ensure asset amount is greater than zero
        require(assetAmount > 0, "Deposit amount must be greater than 0");

        DotcOffer memory offer = dotv2.allOffers(offerId);
        require(
            ASSET_ORACLE[offer.withdrawalAsset.assetAddress] != bytes32(0),
            "Asset not found in our list."
        );

        // Transfer collateral to the contract
        collateralAsset.safeTransferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        _approveIfNeeded(address(collateralAsset), address(dotv2), assetAmount);

        uint256 depositToWithdrawalRate;
        uint256 receivedWithdrawalAmount;

        // Fetch the price of the withdrawal asset and the exchange rate
        (depositToWithdrawalRate, ) = getAssetPrice(
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(collateralAsset),
                amount: assetAmount,
                tokenId: 0,
                assetPrice: AssetPrice(usdc_price_feed, 0, 0)
            }),
            offer.withdrawalAsset,
            offer.offer.offerPrice
        );

        if (isDynamic) {
            // Dynamic Deposit Handling
            dotv2.takeOfferDynamic(
                offerId,
                assetAmount,
                maximumDepositToWithdrawalRate,
                address(this)
            );

            // Fetch updated offer to get the remaining amount after deposit
            DotcOffer memory newOffer = dotv2.allOffers(offerId);
            receivedWithdrawalAmount =
                newOffer.withdrawalAsset.amount -
                offer.withdrawalAsset.amount;
        } else {
            // Fixed Deposit Handling
            dotv2.takeOfferFixed(offerId, assetAmount, address(this));

            // Calculate received withdrawal amount based on fixed rate
            receivedWithdrawalAmount = assetAmount.fullMulDiv(
                depositToWithdrawalRate,
                10 ** IERC20(offer.withdrawalAsset.assetAddress).decimals()
            );
        }

        // Update the user's asset balance in UserAsset mapping
        UserAsset[msg.sender][
            offer.withdrawalAsset.assetAddress
        ] += receivedWithdrawalAmount;

        // Mint LZYBRA tokens based on the asset price and deposit amount
        _mintLZYBRA(
            msg.sender,
            mintAmount,
            depositToWithdrawalRate,
            offer.withdrawalAsset.assetAddress
        );

        // Emit deposit event with relevant details
        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount);
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
        uint256 offerId,
        uint256 assetAmount,
        uint256 maximumDepositToWithdrawalRate,
        bool isDynamic,
        address affiliate
    ) external virtual nonReentrant {
        require(assetAmount > 0, "ZA");

        DotcOffer memory offer = dotv2.allOffers(offerId);
        address depositAssetAddr = offer.depositAsset.assetAddress;
        uint256 userAsset = UserAsset[msg.sender][depositAssetAddr];

        // Ensure user has enough assets to withdraw
        require(
            userAsset >= assetAmount,
            "Withdraw amount exceeds User Assets."
        );
        require(
            offer.depositAsset.assetAddress == address(collateralAsset),
            "Withdraw Asset not USDC."
        );

        // Approve DOTC contract only if needed
        _approveIfNeeded(depositAssetAddr, address(dotv2), assetAmount);

        (uint256 assetRate, ) = getAssetPrice(
            offer.depositAsset,
            offer.withdrawalAsset,
            offer.offer.offerPrice
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
            DotcOffer memory newOffer = dotv2.allOffers(offerId);
            receivingAmount =
                offer.depositAsset.amount -
                newOffer.depositAsset.amount;
        } else {
            // Fixed Offer Withdrawal
            dotv2.takeOfferFixed(offerId, assetAmount, msg.sender);
            receivingAmount = assetAmount != offer.withdrawalAsset.amount
                ? offer.depositAsset.unstandardize(
                    offer.withdrawalAsset.standardize(assetAmount).fullMulDiv(
                        AssetHelper.BPS,
                        offer.offer.offerPrice.unitPrice
                    )
                )
                : offer.depositAsset.amount;
        }

        // Calculate and subtract fees, ensuring valid amount is received
        uint256 fee = feeStored[msg.sender];
        require(receivingAmount > fee, "TZA");
        receivingAmount -= fee;

        // Calculate and repay Lzybra based on user's share
        _repay(
            msg.sender,
            msg.sender,
            depositAssetAddr,
            calc_share(assetAmount, depositAssetAddr, msg.sender)
        );

        // Update user balance in storage
        unchecked {
            UserAsset[msg.sender][depositAssetAddr] = userAsset - assetAmount;
        }

        // Transfer remaining collateral after fee deduction
        collateralAsset.safeTransfer(msg.sender, receivingAmount);

        // Emit withdrawal event with net amount received
        emit WithdrawAsset(msg.sender, depositAssetAddr, receivingAmount);
    }

    /**
     * @notice Keeper liquidates borrowers whose collateral ratio is below badCollateralRatio, using Lzybra provided by Liquidation Provider.
     *
     * Requirements:
     * - provider should authorize Zybra to utilize Lzybra
     * - onBehalfOf Collateral Ratio should be below badCollateralRatio
     * - assetAmount should be less than 50% of collateral
     * - asset Asset to be Liquidated
     * - priceUpdate priceUpdate comes from Hermes Api to get token price from Pyth Oracle  
     
     * @dev After liquidation, borrower's debt is reduced by assetAmount * assetPrice, providers and keepers can receive up to an additional 10% liquidation reward.
     */

    function liquidation(
        address provider,
        address onBehalfOf,
        uint256 assetAmount,
        Asset calldata asset,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant {
        // Fetch collateral ratio and validate liquidation threshold
        address t_address = asset.assetAddress;
        (
            bool shouldLiquidate,
            uint256 collateralRatio
        ) = getCollateralRatioAndLiquidationInfo(
                onBehalfOf,
                t_address,
                priceUpdate
            );
        require(shouldLiquidate, "Above liquidation threshold");

        uint256 maxLiquidationAmount = UserAsset[onBehalfOf][
            t_address
        ] / 2;
        require(assetAmount <= maxLiquidationAmount, "Max 50% collateral");

        // Authorization check for provider
        require(
            Lzybra.allowance(provider, address(this)) != 0 ||
                msg.sender == provider,
            "Provider must authorize"
        );

        uint256 LZYBRAAmount = (assetAmount *
            getAssetPriceOracle(t_address, priceUpdate)) / 1e18;

        uint256 keeperReward = 0;
        uint256 reducedAsset = assetAmount;

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
                keeperReward = (assetAmount * keeperRatio) / 100;
                IERC20(t_address).safeTransfer(
                    msg.sender,
                    keeperReward
                );
            }
        }

        // Repay debt and adjust balances
        _repay(provider, onBehalfOf, t_address, LZYBRAAmount);
        IERC20(t_address).safeTransfer(
            provider,
            reducedAsset - keeperReward
        );

        // Adjust UserAsset storage in a single update
        UserAsset[onBehalfOf][t_address] -=
            reducedAsset +
            keeperReward;

        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            LZYBRAAmount,
            reducedAsset
        );
    }

    function repayingDebt(
        address provider,
        address asset,
        uint256 lzybra_amount,
        bytes[] calldata priceUpdate
    ) external payable virtual {
        require(
            borrowed[asset][provider] >= lzybra_amount,
            "lzybra_amount cannot surpass providers debt"
        );
        (
            ,
            uint256 providerCollateralRatio
        ) = getCollateralRatioAndLiquidationInfo(provider, asset, priceUpdate);

        // Ensure the collateral ratio is healthy (at least 100%) for debt repayment
        require(
            providerCollateralRatio >=
                configurator.getSafeCollateralRatio(address(this))
        );
        _repay(provider, asset, provider, lzybra_amount);
        emit RigidRedemption(
            msg.sender,
            provider,
            asset,
            lzybra_amount,
            collateralAmount
        );
    }

    function claimOffer(uint256 offerId) external nonReentrant {
        DotcOffer memory offer = dotv2.allOffers(offerId);

        // Ensure the caller is the original offer maker
        require(offer.maker == msg.sender, "Only the maker can claim assets");

        // Verify that the offer has been fully taken
        require(
            offer.offerFillType == OfferFillType.FullyTaken,
            "Offer not fully taken yet"
        );

        // Fetch the withdrawal asset amount (now converted to the purchased asset)
        uint256 receivedAmount = offer.withdrawalAsset.amount;
        address purchasedAsset = offer.withdrawalAsset.assetAddress;

        // Update the user's asset balance to reflect the purchased asset
        UserAsset[msg.sender][purchasedAsset] += receivedAmount;

        // Clear USDC holdings and transfer ownership
        UserAsset[msg.sender][address(collateralAsset)] = 0;

        // Repay any outstanding fees and adjust borrowed balance
        _updateFee(msg.sender, purchasedAsset);
        borrowed[msg.sender][purchasedAsset] += borrowed[msg.sender][
            address(collateralAsset)
        ];
        borrowed[msg.sender][address(collateralAsset)] = 0;

        emit OfferClaimed(msg.sender, offerId, purchasedAsset, receivedAmount);
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
        _checkHealth(_provider, asset, _assetPrice);

        Lzybra.mint(_provider, _mintAmount);
        poolTotalCirculation += _mintAmount;
        emit Mint(_provider, _mintAmount);
    }

    /**
     * @notice Burn _provideramount Lzybra to payback minted Lzybra for _onBehalfOf.
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
        Lzybra.transferFrom(_provider, address(this), _amount);
        Lzybra.burn(_provider, _amount);
        borrowed[_onBehalfOf][asset] -= _amount;
        poolTotalCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount);
    }

    function addPriceFeed(
        address _asset,
        bytes32 pythPriceId,
        address chainlinkAggregator
    ) public virtual onlyOwner {
        // Set the Pyth price feed ID for the asset
        ASSET_ORACLE[_asset] = pythPriceId;

        // Set the Chainlink price feed address for the asset if provided
        if (chainlinkAggregator != address(0)) {
            chainlinkOracles[_asset] = chainlinkAggregator;
        }
    }

    /**
     * @dev Get USD value of current collateral asset and minted Lzybra through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
     */
    function _checkHealth(
        address user,
        address asset,
        uint256 price
    ) internal view {
        if (
            ((UserAsset[user][asset] * price * 100) /
                getBorrowed(user, asset)) <
            configurator.getSafeCollateralRatio(address(this))
        ) revert("collateralRatio is Below safeCollateralRatio");
    }

    function _convertDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount; // No conversion needed if decimals are the same
        } else if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals)); // Scale up
        } else {
            return amount / (10 ** (fromDecimals - toDecimals)); // Scale down
        }
    }

    function _updateFee(address user, address asset) internal {
        if (block.timestamp > feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user, asset);
            feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(
        address user,
        address asset
    ) internal view returns (uint256) {
        return
            (borrowed[user][asset] *
                100 *
                (block.timestamp - feeUpdatedAt[user])) /
            (86_400 * 365) /
            10_000;
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
                (amount - currentAllowance) * 20
            );
            require(success, "Approval failed");
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

    function calc_share(
        uint256 amount,
        address asset,
        address user
    ) internal view returns (uint256) {
        uint256 borrowedAmount = borrowed[user][asset];
        uint256 userAssetAmount = UserAsset[user][asset];
        require(userAssetAmount > 0, "UserAsset must be greater than zero");

        // Calculate share with multiplication before division to maintain precision
        return (borrowedAmount * amount) / userAssetAmount;
    }

    function getCollateralRatioAndLiquidationInfo(
        address user,
        address asset,
        bytes[] calldata priceUpdate
    ) public view returns (bool shouldLiquidate, uint256 collateralRatio) {
        // Get the user's asset amount and the current price of the asset
        uint256 userCollateralAmount = UserAsset[user][asset];
        uint256 AssetPrice = getAssetPriceOracle(asset, priceUpdate);

        // Calculate the USD value of the collateral
        uint256 collateralValueInUSD = (userCollateralAmount * AssetPrice) /
            1e18;

        // Get the user's total borrowed amount in LZYBRA (assumed to be in USD)
        uint256 userDebtAmount = getBorrowed(user, asset);

        // Avoid division by zero: if the user has no debt, return max collateral ratio and no liquidation
        if (userDebtAmount == 0) {
            return (false, type(uint256).max); // No liquidation if no debt, max ratio
        }

        // Calculate the collateral ratio
        collateralRatio = (collateralValueInUSD * 1e18) / userDebtAmount;

        // Determine if the collateral ratio falls below the liquidation threshold
        uint256 badCollateralRatio = configurator.getBadCollateralRatio(
            address(this)
        );
        shouldLiquidate = collateralRatio < badCollateralRatio;
    }

    function getAssetPrice(
        Asset memory depositAsset,
        Asset memory withdrawalAsset,
        OfferPrice memory offerPrice
    ) public view returns (uint256, uint256) {
        return
            AssetHelper.getRateAndPrice(
                depositAsset,
                withdrawalAsset,
                offerPrice
            );
    }

    function getAssetPriceOracle(
        address _asset,
        bytes[] calldata priceUpdate
    ) public payable returns (uint256) {
        // Calculate the fee required to update the price
        uint fee = pyth.getUpdateFee(priceUpdate);

        // Update the price feeds - Pyth's contract will verify signatures internally
        try pyth.updatePriceFeeds{value: fee}(priceUpdate) {
            // No additional signature check needed since Pyth already performs this
        } catch {
            revert("Invalid or tampered price update.");
        }

        int64 priceInt;

        // Attempt to get the primary price feed from Pyth (Pyth returns prices with 8 decimals)
        try pyth.getPriceNoOlderThan(ASSET_ORACLE[_asset], 60) returns (
            PythStructs.Price memory priceData
        ) {
            priceInt = priceData.price;
        } catch {
            // Fallback mechanism: use Chainlink price if available
            return getFallbackPrice(_asset);
        }

        // Ensure the price is non-negative
        require(priceInt > 0, "Price cannot be negative.");

        // Pyth returns prices with 8 decimals, scale to 18 decimals
        uint256 scaledPrice = _convertDecimals(
            uint256(int256(priceInt)),
            8,
            18
        );

        // Return the price in 18 decimals
        return scaledPrice;
    }

    // Fallback price function for Chainlink (already 8 decimals)
    function getFallbackPrice(address _asset) internal view returns (uint256) {
        // Get the Chainlink oracle address for the asset
        address chainlinkOracle = chainlinkOracles[_asset];

        // Revert if no Chainlink oracle exists for this asset
        require(
            chainlinkOracle != address(0),
            "No Chainlink oracle available for this asset."
        );

        // Initialize the Chainlink price feed interface
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            chainlinkOracle
        );

        // Fetch the latest price from Chainlink
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // Ensure the price is non-negative
        require(price > 0, "Chainlink price feed returned a negative value.");

        // Chainlink returns prices with 8 decimals, so we scale to 18 decimals
        return _convertDecimals(uint256(price), 8, 18);
    }
}
