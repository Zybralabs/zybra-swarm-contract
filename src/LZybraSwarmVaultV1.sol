// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AssetHelper} from "./helpers/AssetHelper.sol";
import {Asset, AssetType, AssetPrice, OfferStruct, OfferPrice, DotcOffer} from "./structures/DotcStructuresV2.sol";
import {SafeTransferLib, FixedPointMathLib, FixedPointMathLib} from "./exports/ExternalExports.sol";
import {OfferHelper} from "./helpers/OfferHelper.sol";
import {DotcOfferHelper} from "./helpers/DotcOfferHelper.sol";

import "./interfaces/IERC7540.sol";

interface IPoolManager {
    function getTranchePrice(
        uint64 poolId,
        bytes16 trancheId,
        address asset
    ) external view returns (uint128 price, uint64 computedAt);
}

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

    ILZYBRA public lybra;
    address public usdc_price_feed;
    Iconfigurator public configurator;
    IDotcV2 public dotv2;
    IPyth public pyth;
    IERC20 public collateralAsset;
    uint256 poolTotalCirculation;

    mapping(address => mapping(address => uint256)) public UserAsset; // User withdraw request tranche asset amount
    mapping(address => mapping(address => uint256)) borrowed;
    mapping(address => uint256) feeStored;
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

    constructor(
        address _collateralAsset,
        address _lzybra,
        address _dotcv2,
        address _initialOwner,
        address _configurator,
        address pythAddress
    ) Ownable(_initialOwner) {
        lybra = ILZYBRA(_lzybra);
        dotv2 = IDotcV2(_dotcv2);
        collateralAsset = IERC20(_collateralAsset);
        configurator = Iconfigurator(_configurator);
        pyth = IPyth(pythAddress);
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
        OfferStruct calldata offer
    ) external virtual onlyExistingAsset(withdrawalAsset.assetAddress) nonReentrant {
        require(assetAmount > 0, "Deposit amount must be greater than 0");

        // Transfer collateral to the contract
        collateralAsset.safeTransferFrom(msg.sender, address(this), assetAmount);

      
        collateralAsset.approve(address(dotv2), assetAmount);

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

        // Fetch the price of the withdrawal asset and the exchange rate
        (uint256 depositToWithdrawalRate, ) = getAssetPrice(
            usdc_asset,
            withdrawalAsset,
            offer.offerPrice
        );

        // Mint lybra tokens based on the asset price and deposit amount
        _mintLZYBRA(
            msg.sender,
            assetAmount,
            depositToWithdrawalRate,
            withdrawalAsset.assetAddress
        );

        // Emit the DepositAsset event after state changes
        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount);
    }
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
        uint256 mintAmount
    ) external virtual nonReentrant {
        // Ensure asset amount is greater than zero
        require(assetAmount > 0, "Deposit amount must be greater than 0");
    
        DotcOffer memory offer = dotv2.allOffers(offerId);
        require(
            ASSET_ORACLE[offer.withdrawalAsset.assetAddress] != bytes32(0),
            "Asset not found in our list."
        );

        // Transfer collateral to the contract
        IERC20(offer.withdrawalAsset.assetAddress).safeTransferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        // Approve the DOTC contract to handle the transferred amount
        // Using a fixed allowance to avoid potential race conditions
        IERC20(offer.withdrawalAsset.assetAddress).safeApprove(
            address(dotv2),
            assetAmount
        );

        // Create the offer in dotv2
        dotv2.takeOfferFixed(offerId, assetAmount, address(this));


        // Fetch the price of the withdrawal asset and the exchange rate
        (uint256 depositToWithdrawalRate, ) = getAssetPrice(
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

        // Mint LZYBRA tokens based on the asset price and deposit amount
        _mintLZYBRA(
            msg.sender,
            mintAmount,
            depositToWithdrawalRate,
            offer.withdrawalAsset.assetAddress
        );

        // Emit deposit event
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


    function withdraw(uint256 offerId, uint256 asset_amount) external virtual {
        require(asset_amount != 0, "ZA");
        _withdrawTakeOfferFixed(msg.sender, offerId, asset_amount);
    }

    function withdraw(
        uint256 offerId,
        uint256 maximumDepositToWithdrawalRate,
        uint256 asset_amount
    ) external virtual {
        require(asset_amount != 0, "ZA");
        _withdrawTakeOfferDynamic(
            msg.sender,
            offerId,
            asset_amount,
            maximumDepositToWithdrawalRate,
            msg.sender
        );
    }

    /**
     * @notice Keeper liquidates borrowers whose collateral ratio is below badCollateralRatio, using lybra provided by Liquidation Provider.
     *
     * Requirements:
     * - provider should authorize Zybra to utilize lybra
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
) external payable onlyExistingAsset(asset.assetAddress) nonReentrant {
    // Fetch asset price and collateral ratio
    uint256 assetPrice = getAssetPriceOracle(asset.assetAddress, priceUpdate);
    address assetAddress = asset.assetAddress;

    // Calculate collateral value and borrowed value
    uint256 collateralValue = UserAsset[onBehalfOf][assetAddress] * assetPrice;
    uint256 borrowedValue = getBorrowed(onBehalfOf, assetAddress);
     require(borrowedValue > 0, "Borrowed value must be greater than zero");
    uint256 onBehalfOfCollateralRatio = (collateralValue * 100) / borrowedValue;

    // Check liquidation limits
    require(assetAmount * 2 <= UserAsset[onBehalfOf][assetAddress], "a max of 50% collateral can be liquidated");
    require(onBehalfOfCollateralRatio < configurator.getBadCollateralRatio(address(this)), "Borrower's collateral ratio should be below badCollateralRatio");
    
    // Check provider authorization
    require(
        lybra.allowance(provider, address(this)) != 0 || msg.sender == provider,
        "Provider should authorize liquidation lybra"
    );

    // Calculate lybra amount to repay
    uint256 LZYBRAAmount = (assetAmount * assetPrice) / 1e18;

    // Redeem user's collateral and repay their debt
    _repay(provider, onBehalfOf, assetAddress, LZYBRAAmount);

    // Calculate reduced asset based on collateral ratio
    uint256 reducedAsset = assetAmount;
    if (onBehalfOfCollateralRatio > 1e20) {
        reducedAsset = (onBehalfOfCollateralRatio < 11e19) 
            ? (assetAmount * onBehalfOfCollateralRatio) / 1e20 
            : (assetAmount * 11) / 10;
    }

    // Calculate keeper's reward
    uint256 keeperRatio = configurator.vaultKeeperRatio(address(this));
    uint256 reward2keeper = 0;

    if (msg.sender != provider && onBehalfOfCollateralRatio >= (1e20 + keeperRatio * 1e18)) {
        reward2keeper = (assetAmount * keeperRatio) / 100;
        IERC20(assetAddress).safeTransfer(msg.sender, reward2keeper); // Reward keeper
    }

    // Transfer the remaining reduced asset to the provider
    IERC20(assetAddress).safeTransfer(provider, reducedAsset - reward2keeper);

    // Emit liquidation event
    emit LiquidationRecord(provider, msg.sender, onBehalfOf, LZYBRAAmount, reducedAsset);
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

        lybra.mint(_provider, _mintAmount);
        poolTotalCirculation += _mintAmount;
        emit Mint(_provider, _mintAmount);
    }

    /**
     * @notice Burn _provideramount lybra to payback minted lybra for _onBehalfOf.
     *
     * @dev rePAY the User debt so the Collateral Ratio for user is mantained.
     */
    function _repay(
        address _provider,
        address _onBehalfOf,
        address asset,
        uint256 _amount
    ) internal virtual {
        _updateFee(_onBehalfOf,asset);
        uint256 totalFee = feeStored[_onBehalfOf];
        uint256 amount = borrowed[_onBehalfOf][asset] + totalFee >= _amount
            ? _amount
            : borrowed[_onBehalfOf][asset] + totalFee;
        if (amount > totalFee) {
            feeStored[_onBehalfOf] = 0;
            lybra.transferFrom(_provider, address(configurator), totalFee);
            lybra.burn(_provider, amount - totalFee);
            borrowed[_onBehalfOf][asset] -= amount - totalFee;
            poolTotalCirculation -= amount - totalFee;
        } else {
            feeStored[_onBehalfOf] = totalFee - amount;
            lybra.transferFrom(_provider, address(configurator), amount);
        }
        try configurator.distributeRewards() {} catch {}
        emit Burn(_provider, _onBehalfOf, amount);
    }

    function _withdrawTakeOfferFixed(
        address _provider,
        uint256 offerId,
        uint256 amountToSend
    ) internal virtual {
        // Cache storage reads for optimal gas consumption
        DotcOffer memory offer = dotv2.allOffers(offerId);
        address depositAssetAddr = offer.depositAsset.assetAddress;
        uint256 userAsset = UserAsset[_provider][depositAssetAddr];
        uint256 fee = feeStored[_provider];

        // Early reverts to save gas on failure paths
        require(
            offer.depositAsset.assetAddress == address(collateralAsset),
            "Withdraw Asset not USDC."
        );
        require(
            userAsset >= amountToSend,
            "Withdraw amount exceeds User Assets."
        );

        // Check health only if there are borrowed assets
        if (getBorrowed(_provider, depositAssetAddr) > 0) {
            _checkHealth(_provider, depositAssetAddr, assetRate);
        }


        (uint256 assetRate, ) = getAssetPrice(
            offer.depositAsset,
            offer.withdrawalAsset,
            offer.offer.offerPrice
        );

        
        // Calculate receiving amount based on offer conditions
        uint256 receivingAmount = amountToSend != offer.withdrawalAsset.amount
            ? offer.depositAsset.unstandardize(
                offer.withdrawalAsset.standardize(amountToSend).fullMulDiv(
                    AssetHelper.BPS,
                    offer.offer.offerPrice.unitPrice
                )
            )
            : offer.depositAsset.amount;

        // Require valid amount is received and deduct the fee inline
        require(receivingAmount > fee, "TZA");

        // Call external function at the end of state manipulations
        dotv2.takeOfferFixed(offerId, amountToSend, _provider);

        // Calculate and repay lybra
        _repay(
            msg.sender,
            _provider,
            depositAssetAddr,
            calc_share(amountToSend, depositAssetAddr, msg.sender)
        );

        // Update user balance in storage
        unchecked {
            UserAsset[_provider][depositAssetAddr] =
                userAsset -
                amountToSend;
        }

        // Transfer remaining collateral minus fee
        collateralAsset.safeTransfer(_provider, receivingAmount - fee);

        // Emit event, calculating received amount inline
        emit WithdrawAsset(
            _provider,
            depositAssetAddr,
            receivingAmount - fee
        );
    }

    function _withdrawTakeOfferDynamic(
        address _provider,
        uint256 offerId,
        uint256 amountToSend,
        uint256 maximumDepositToWithdrawalRate,
        address affiliate
    ) internal virtual {
        // Cache storage reads for optimal gas consumption
        DotcOffer memory offer = dotv2.allOffers(offerId);
        address depositAssetAddr = offer.depositAsset.assetAddress;
        uint256 userAsset = UserAsset[_provider][depositAssetAddr];
        uint256 fee = feeStored[_provider];

        // Early reverts to save gas on failure paths
        require(
            offer.withdrawalAsset.assetAddress == address(collateralAsset),
            "Withdraw Asset not USDC."
        );
        require(
            userAsset >= amountToSend,
            "Withdraw amount exceeds User Assets."
        );
        
        // Check health only if there are borrowed assets
        if (getBorrowed(_provider, depositAssetAddr) > 0) {
            _checkHealth(_provider, depositAssetAddr, assetRate);
        }


        (uint256 assetRate, ) = getAssetPrice(
            offer.depositAsset,
            offer.withdrawalAsset,
            offer.offer.offerPrice
        );

    
        // Call external function at the end of state manipulations
        dotv2.takeOfferDynamic(
            offerId,
            amountToSend,
            maximumDepositToWithdrawalRate,
            _provider
        );

        // Calculate receiving amount based on offer conditions
        DotcOffer memory new_offer = dotv2.allOffers(offerId);
        //USDC Asset
        uint256 receivingAmount = offer.depositAsset.amount -
            new_offer.depositAsset.amount;

        // Require valid amount is received and deduct the fee inline
        require(receivingAmount > fee, "TZA");

        // Calculate and repay lybra
        _repay(
            msg.sender,
            _provider,
            depositAssetAddr,
            calc_share(amountToSend, depositAssetAddr, msg.sender)
        );

        // Update user balance in storage
        unchecked {
            UserAsset[_provider][depositAssetAddr] =
                userAsset -
                amountToSend;
        }

        // Transfer remaining collateral minus fee
        collateralAsset.safeTransfer(_provider, receivingAmount - fee);

        // Emit event, calculating received amount inline
        emit WithdrawAsset(
            _provider,
            depositAssetAddr,
            receivingAmount - fee
        );
    }


    function addPriceFeed(address _asset, bytes32 priceId) public virtual onlyOwner{
        
        ASSET_ORACLE[_asset] = priceId;
    }
    /**
     * @dev Get USD value of current collateral asset and minted lybra through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
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
     * @dev Returns the current borrowing amount for the user, including borrowed shares and accumulated fees.
     * @param user The address of the user.
     * @return The total borrowing amount for the user.
     */
    function getBorrowed(
        address user,
        address asset
    ) public view returns (uint256) {
        return borrowed[user][asset] + feeStored[user] + _newFee(user, asset);
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
        return (borrowedAmount * (amount / userAssetAmount));
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
) public returns (uint256) {
    // Calculate the fee required to update the price
    uint fee = pyth.getUpdateFee(priceUpdate);
    
    // Update the price feeds
    pyth.updatePriceFeeds{value: fee}(priceUpdate);

    // Fetch the price as int64
    int64 priceInt = pyth.getPriceNoOlderThan(ASSET_ORACLE[_asset], 60).price;

    // Ensure the price is non-negative
    require(priceInt >= 0, "Price cannot be negative.");

    // Convert to uint256 safely and return the price
     return uint256(int256(priceInt)) * 10 ** 12;

}
}