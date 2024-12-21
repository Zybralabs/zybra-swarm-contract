// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "./interfaces/AggregatorV2V3Interface.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {AssetHelper} from "./helpers/AssetHelper.sol";
import {Asset, AssetType, AssetPrice, OfferStruct, OfferPrice, DotcOffer, OfferFillType} from "./structures/DotcStructuresV2.sol";
import {SafeTransferLib, FixedPointMathLib} from "./exports/ExternalExports.sol";
import {OfferHelper} from "./helpers/OfferHelper.sol";
import {DotcOfferHelper} from "./helpers/DotcOfferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";



contract LzybraVault is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable  {

    using SafeTransferLib for address;
    /// @dev Used for precise calculations.
    using FixedPointMathLib for uint256;
    /// @dev Used for Asset interaction.
    using AssetHelper for Asset;

    /// @dev Used for Offer interaction.
    using OfferHelper for OfferStruct;
    /// @dev Used for Dotc Offer interaction.
    using DotcOfferHelper for DotcOffer;

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



    mapping(address => mapping(address => uint256)) public userAssets; // User withdraw request tranche asset amount
    mapping(address => mapping(address => uint256)) public borrowed;
    mapping(address => uint256) public feeStored;
    mapping(address => uint256) _feeUpdatedAt;
    mapping(address => Oracles) public assetOracles;


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
    event OfferClaimed(address, uint256, address, uint256);
    event repayDebt(
            address,
            address,
            address,
            uint256
        );

    modifier onlyExistingAsset(address _asset) {
    Oracles memory oracles = assetOracles[_asset];
    require(
        oracles.chainlink != address(0) || oracles.pyth != bytes32(0),
        "Asset not found in the oracles."
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
        usdc_collateralAsset = IERC20(_collateralAsset);
        lzybra = ILZYBRA(_lzybra);
        dotv2 = IDotcV2(_dotcv2);
        configurator = Iconfigurator(_configurator);
        assetOracles[_usdc_price_feed] = Oracles({
            chainlink: _usdc_price_feed,
            pyth: bytes32(0)
        });
        pyth = IPyth(_pythAddress);

        // Initialize mappings as needed
        poolTotalCirculation = 0; // Defaults to 0, but explicitly set for clarity

        // Initialize fees and other mappings
        // Set default timestamps and fee storage
        // _feeUpdatedAt and feeStored mappings will start with zero values
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
        usdc_collateralAsset.transferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        // Approve DOTC contract only if needed
        _approveIfNeeded(address(usdc_collateralAsset), address(dotv2), assetAmount);

        // Create an Asset struct for the deposit
        Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(usdc_collateralAsset),
            amount: assetAmount,
            tokenId: 0,
            assetPrice: AssetPrice(assetOracles[address(usdc_collateralAsset)].chainlink, 0, 0)
        });

        // Create the offer in dotv2
        dotv2.makeOffer(usdc_asset, withdrawalAsset, offer);

        userAssets[msg.sender][usdc_asset.assetAddress] += assetAmount;
        uint256  depositToWithdrawalRate = _getFallbackPrice(address(usdc_collateralAsset));
        // Mint lzybra tokens based on the asset price and deposit amount
        _mintLZYBRA(
            msg.sender,
            assetAmount,
            depositToWithdrawalRate,
            usdc_asset.assetAddress
        );

        // Emit the DepositAsset event after state changes
        emit DepositAsset(msg.sender, address(usdc_collateralAsset), assetAmount);
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
    assetOracles[offer.withdrawalAsset.assetAddress].chainlink != address(0) ||
    assetOracles[offer.withdrawalAsset.assetAddress].pyth != bytes32(0),
    "Asset not found in our oracle list."
);

        // Transfer collateral to the contract
        usdc_collateralAsset.transferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        _approveIfNeeded(address(usdc_collateralAsset), address(dotv2), assetAmount);

        uint256 depositToWithdrawalRate;
        uint256 receivedWithdrawalAmount;

        // Fetch the price of the withdrawal asset and the exchange rate
        (depositToWithdrawalRate, ) = getAssetPrice(
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(usdc_collateralAsset),
                amount: assetAmount,
                tokenId: 0,
                assetPrice: AssetPrice(assetOracles[address(usdc_collateralAsset)].chainlink, 0, 0)
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

        // Update the user's asset balance in userAsset mapping
        userAssets[msg.sender][
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
        emit DepositAsset(msg.sender, address(usdc_collateralAsset), assetAmount);
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
        uint256 userAsset = userAssets[msg.sender][depositAssetAddr];

        // Ensure user has enough assets to withdraw
        require(
            userAsset >= assetAmount,
            "Withdraw amount exceeds User Assets."
        );
        require(
            offer.depositAsset.assetAddress == address(usdc_collateralAsset),
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

        // Calculate and repay lzybra based on user's share
        _repay(
            msg.sender,
            msg.sender,
            depositAssetAddr,
            _calcShare(assetAmount, depositAssetAddr, msg.sender)
        );

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
        // Fetch collateral ratio and validate liquidation threshold
        address tAddress = asset.assetAddress;
        (
            bool shouldLiquidate,
            uint256 collateralRatio
        ) = getCollateralRatioAndLiquidationInfo(
                onBehalfOf,
                tAddress,
                priceUpdate
            );
        require(shouldLiquidate, "Above liquidation threshold");

        uint256 maxLiquidationAmount = userAssets[onBehalfOf][
            tAddress
        ] / 2;
        require(assetAmount <= maxLiquidationAmount, "Max 50% collateral");

        // Authorization check for provider
        require(
            lzybra.allowance(provider, address(this)) != 0 ||
                msg.sender == provider,
            "Provider must authorize"
        );

        uint256 lzybraAmount = (assetAmount *
            getAssetPriceOracle(tAddress, priceUpdate)) / 1e18;

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
                IERC20(tAddress).transfer(
                    msg.sender,
                    keeperReward
                );
            }
        }

        // Repay debt and adjust balances
        _repay(provider, onBehalfOf, tAddress, lzybraAmount);
        IERC20(tAddress).transfer(
            provider,
            reducedAsset - keeperReward
        );

        // Adjust userAsset storage in a single update
        userAssets[onBehalfOf][tAddress] -=
            reducedAsset +
            keeperReward;

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
        require(
            borrowed[asset][provider] >= lzybraAmount,
            "lzybraAmount cannot surpass providers debt"
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
        _repay(provider, asset, provider, lzybraAmount);
        emit repayDebt(
            msg.sender,
            provider,
            asset,
            lzybraAmount
            
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
        userAssets[msg.sender][purchasedAsset] += receivedAmount;

        // Clear USDC holdings and transfer ownership
        userAssets[msg.sender][address(usdc_collateralAsset)] = 0;

        // Repay any outstanding fees and adjust borrowed balance
        _updateFee(msg.sender, purchasedAsset);
        borrowed[msg.sender][purchasedAsset] += borrowed[msg.sender][
            address(usdc_collateralAsset)
        ];
        borrowed[msg.sender][address(usdc_collateralAsset)] = 0;

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
            "At least one oracle must be set"
        );

        assetOracles[asset] = Oracles({
            chainlink: chainlinkOracle,
            pyth: pythOracle
        });
    }

    /**
     * @dev Get USD value of current collateral asset and minted lzybra through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
     */
    function _checkHealth(
        address user,
        address asset,
        uint256 price
    ) internal view {
        if (
            ((userAssets[user][asset] * price * 100) /
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
        if (block.timestamp > _feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user, asset);
            _feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(
        address user,
        address asset
    ) internal view returns (uint256) {
        return
            (borrowed[user][asset] *
                100 *
                (block.timestamp - _feeUpdatedAt[user])) /
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

    function _calcShare(
        uint256 amount,
        address asset,
        address user
    ) internal view returns (uint256) {
        uint256 borrowedAmount = borrowed[user][asset];
        uint256 userAssetAmount = userAssets[user][asset];
        require(userAssetAmount > 0, "userAsset must be greater than zero");

        // Calculate share with multiplication before division to maintain precision
        return (borrowedAmount * amount) / userAssetAmount;
    }

    function getCollateralRatioAndLiquidationInfo(
        address user,
        address asset,
        bytes[] calldata priceUpdate
    ) public view returns (bool shouldLiquidate, uint256 collateralRatio) {
        // Get the user's asset amount and the current price of the asset
        uint256 userCollateralAmount = userAssets[user][asset];
        uint256 assetPrice = getAssetPriceOracle(asset, priceUpdate);

        // Calculate the USD value of the collateral
        uint256 collateralValueInUSD = (userCollateralAmount * assetPrice) /
            1e18;

        // Get the user's total borrowed amount in LZYBRA (assumed to be in USD)
        uint256 userDebtAmount = getBorrowed(user, asset);

        // Avoid division by zero: if the user has no debt, return max collateral ratio and no liquidation
        if (userDebtAmount == 0) {
            return (false, type(uint256).max); // No liquidation if no debt, max ratio
        }

        // Calculate the collateral ratio
        collateralRatio = ((collateralValueInUSD * 1e18) / userDebtAmount) * 100;

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
    ) internal view returns (uint256, uint256) {
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
    Oracles memory oracles = assetOracles[_asset];

    // Validate that the asset has at least one oracle set
    require(
        oracles.chainlink != address(0) || oracles.pyth != bytes32(0),
        "No oracles available for this asset."
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
            revert("Invalid or tampered Pyth price update.");
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
        require(priceInt > 0, "Pyth price cannot be negative.");

        // Pyth returns prices with 8 decimals, scale to 18 decimals
        uint256 scaledPrice = _convertDecimals(
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
    require(
        oracles.chainlink != address(0),
        "No Chainlink oracle available for this asset."
    );

    // Initialize the Chainlink price feed interface
    AggregatorV3Interface _priceFeed = AggregatorV3Interface(oracles.chainlink);

    // Fetch the latest price from Chainlink
    (, int256 price, , , ) = _priceFeed.latestRoundData();

    // Ensure the price is non-negative
    require(price > 0, "Chainlink price feed returned a negative value.");

    // Chainlink returns prices with 8 decimals, scale to 18 decimals
    return _convertDecimals(uint256(price), 8, 18);
}


}
