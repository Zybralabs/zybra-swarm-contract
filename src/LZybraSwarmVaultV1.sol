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
import { AssetHelper } from "./helpers/AssetHelper.sol";
import {Asset, AssetType, AssetPrice, OfferStruct,OfferPrice, DotcOffer} from "./structures/DotcStructuresV2.sol";
import { SafeTransferLib, FixedPointMathLib, FixedPointMathLib} from "./exports/ExternalExports.sol";
import { OfferHelper } from "./helpers/OfferHelper.sol";
import { DotcOfferHelper } from "./helpers/DotcOfferHelper.sol";

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

    ILZYBRA public immutable LZYBRA;
    address public immutable usdc_price_feed;
    Iconfigurator public configurator;
    IDotcV2 public DOTCV2;
    IERC20 public immutable collateralAsset;
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
    event CancelDepositRequest(
        address indexed onBehalfOf,
        address asset
    );

    event WithdrawAsset(
        address indexed sponsor,
        address asset,
        uint256 amount
    );
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
    constructor(
        address _collateralAsset,
        address _lzybra,
        address _dotcv2,
        address _initialOwner,
        address _coonfigurator
    ) Ownable(_initialOwner){
        LZYBRA = ILZYBRA(_lzybra);
        DOTCV2 = IDotcV2(_dotcv2);
        collateralAsset = IERC20(_collateralAsset);
        configurator =  Iconfigurator(_coonfigurator);
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
    ) external virtual {
        require(assetAmount > 0, "Deposit amount must be greater than 0");

        // Transfer collateral to the contract
        collateralAsset.safeTransferFrom(msg.sender, address(this), assetAmount);

        // Approve the DOTC contract to handle the transferred amount
        collateralAsset.approve(address(DOTCV2), assetAmount);

        // Create an Asset struct for the deposit
         Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(collateralAsset),
            amount: assetAmount,
                        tokenId: 0,

            assetPrice: AssetPrice(usdc_price_feed,0,0)
        });

        // Create the offer in DOTCV2
        DOTCV2.makeOffer(usdc_asset, withdrawalAsset, offer);

        // Fetch the price of the withdrawal asset and the exchange rate
        (uint256 depositToWithdrawalRate, ) = getAssetPrice(usdc_asset, withdrawalAsset, offer.offerPrice);

        // Mint LZYBRA tokens based on the asset price and deposit amount
        _mintLZYBRA(msg.sender, assetAmount ,depositToWithdrawalRate,withdrawalAsset.assetAddress);

        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount);
    }


    function deposit(
        uint256 assetAmount,
        uint256 offerId
    ) external virtual { 
        require(assetAmount > 0, "Deposit amount must be greater than 0");
        DotcOffer memory offer = DOTCV2.allOffers(offerId);
        // Transfer collateral to the contract
        collateralAsset.safeTransferFrom(msg.sender, address(this), assetAmount);

        // Approve the DOTC contract to handle the transferred amount
        collateralAsset.approve(address(DOTCV2), assetAmount);

        // Create the offer in DOTCV2
        DOTCV2.takeOfferFixed(offerId, assetAmount, msg.sender);
   Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(collateralAsset),
            amount: assetAmount,
                        tokenId: 0,

            assetPrice: AssetPrice(usdc_price_feed,0,0)
        });
        // Fetch the price of the withdrawal asset and the exchange rate
        // Fix offerId
        (uint256 depositToWithdrawalRate, ) = getAssetPrice(usdc_asset, offer.withdrawalAsset, offer.offer.offerPrice);
        // Mint LZYBRA tokens based on the asset price and deposit amount
        _mintLZYBRA(msg.sender, assetAmount, depositToWithdrawalRate,offer.withdrawalAsset.assetAddress);

        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount);
    }



 

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawAsset` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `asset_amount` Must be higher than 0.
     
     * @dev Withdraw collateral. Check user’s collateral ratio after withdrawal, should be higher than `safeCollateralRatio`
     */
    function withdraw(uint256 offerId, uint256 asset_amount) external virtual {
        require(asset_amount != 0, "ZA");
        _withdrawTakeOfferFixed(msg.sender, offerId,asset_amount);
    }



    function withdraw(uint256 offerId, uint256 maximumDepositToWithdrawalRate, uint256 asset_amount) external virtual {
        require(asset_amount != 0, "ZA");
        _withdrawTakeOfferDynamic(msg.sender, offerId,asset_amount, maximumDepositToWithdrawalRate,msg.sender);
    }

    
    /**
     * @notice Keeper liquidates borrowers whose collateral ratio is below badCollateralRatio, using LZYBRA provided by Liquidation Provider.
     *
     * Requirements:
     * - onBehalfOf Collateral Ratio should be below badCollateralRatio
     * - assetAmount should be less than 50% of collateral
     * - provider should authorize Zybra to utilize LZYBRA
     
     * @dev After liquidation, borrower's debt is reduced by assetAmount * assetPrice, providers and keepers can receive up to an additional 10% liquidation reward.
     */
// remaining: fix the liquidation function..

    function liquidation(
    address provider,
    address onBehalfOf,
    uint256 assetAmount,
    Asset calldata asset
) external virtual {
    // Fetch asset price and collateral ratio
       Asset memory usdc_asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(collateralAsset),
            amount: assetAmount,
                        tokenId: 0,

            assetPrice: AssetPrice(usdc_price_feed,0,0)
        });
     (uint256 assetPrice,) = getAssetPrice(asset,usdc_asset);
    address assetAddress = asset.assetAddress;

    // Calculate collateral ratio
    uint256 collateralValue = UserAsset[onBehalfOf][assetAddress] * assetPrice;
    uint256 borrowedValue = getBorrowed(onBehalfOf,assetAddress);
    uint256 onBehalfOfCollateralRatio = (collateralValue * 100) / borrowedValue;
       require(assetAmount * 2 <= UserAsset[onBehalfOf][assetAddress], "a max of 50% collateral can be liquidated");
        require(LZYBRA.allowance(provider, address(this)) != 0 || msg.sender == provider, "provider should authorize to provide liquidation peUSD");

    // Check if collateral ratio falls below the badCollateralRatio threshold
    require(
        onBehalfOfCollateralRatio < configurator.getBadCollateralRatio(address(this)),
        "Borrower's collateral ratio should be below badCollateralRatio"
    );


    // Check if the provider is authorized to perform liquidation
    require(
        LZYBRA.allowance(provider, address(this)) != 0 || msg.sender == provider,
        "Provider should authorize liquidation LZYBRA"
    );

    // Calculate LZYBRA amount to repay
    uint256 LZYBRAAmount = (assetAmount * assetPrice) / 1e18;

    // Redeem user's collateral and repay their debt
    _repay(provider, onBehalfOf,assetAddress, LZYBRAAmount);
    // _repay(provider, onBehalfOf,assetAddress, calc_share(assetAmount, assetAddress, provider));

    // Adjust the asset amount based on the collateral ratio
    uint256 reducedAsset = assetAmount;
    if (onBehalfOfCollateralRatio > 1e20 && onBehalfOfCollateralRatio < 11e19) {
        reducedAsset = (assetAmount * onBehalfOfCollateralRatio) / 1e20;
    }
    if (onBehalfOfCollateralRatio >= 11e19) {
        reducedAsset = (assetAmount * 11) / 10;
    }

    // Calculate rewards for the keeper (provider)
    //config solve
    uint256 keeperRatio = configurator.vaultKeeperRatio(address(this));
    uint256 reward2keeper;
    if (
        msg.sender != provider && 
        onBehalfOfCollateralRatio >= (1e20 + keeperRatio * 1e18)
    ) {
        reward2keeper = (assetAmount * keeperRatio) / 100;
        IERC20(assetAddress).safeTransfer(msg.sender, reward2keeper); // Reward keeper
    }

    // Transfer the remaining reduced asset to the provider
    IERC20(assetAddress).safeTransfer(provider, reducedAsset - reward2keeper);

    // Emit liquidation event
    emit LiquidationRecord(
        provider,
        msg.sender,
        onBehalfOf,
        LZYBRAAmount,
        reducedAsset
    );
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
  
        _updateFee(_provider,asset);
        borrowed[_provider][asset] += _mintAmount;
        _checkHealth(_provider,asset, _assetPrice);

        LZYBRA.mint(_provider, _mintAmount);
        poolTotalCirculation += _mintAmount;
        emit Mint(_provider, _mintAmount);
    }

    /**
     * @notice Burn _provideramount LZYBRA to payback minted LZYBRA for _onBehalfOf.
     *
     * @dev rePAY the User debt so the Collateral Ratio for user is mantained.
     */
    function _repay(
        address _provider,
        address _onBehalfOf,
        address asset,
        uint256 _amount
    ) internal virtual {
     
         _updateFee(_onBehalfOf);
        uint256 totalFee = feeStored[_onBehalfOf];
        uint256 amount = borrowed[_onBehalfOf][asset] + totalFee >= _amount ? _amount : borrowed[_onBehalfOf] + totalFee;
        if(amount > totalFee) {
            feeStored[_onBehalfOf] = 0;
            LZYBRA.transferFrom(_provider, address(configurator), totalFee);
            LZYBRA.burn(_provider, amount - totalFee);
            borrowed[_onBehalfOf][asset] -= amount - totalFee;
            poolTotalCirculation -= amount - totalFee;
        } else {
            feeStored[_onBehalfOf] = totalFee - amount;
            LZYBRA.transferFrom(_provider, address(configurator), amount);
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
    DotcOffer memory offer = DOTCV2.allOffers(offerId);
    address withdrawalAssetAddr = offer.withdrawalAsset.assetAddress;
    uint256 userAsset = UserAsset[_provider][withdrawalAssetAddr];
    uint256 fee = feeStored[_provider];

    // Early reverts to save gas on failure paths
    require(offer.depositAsset.assetAddress == address(collateralAsset), "Withdraw Asset not USDC.");
    require(userAsset >= amountToSend && userAsset > 0, "Withdraw amount exceeds User Assets.");

    (uint256 assetRate, ) = getAssetPrice(offer.depositAsset, offer.withdrawalAsset, offer.offer.offerPrice);

    // Check health only if there are borrowed assets
    if (getBorrowed(_provider,withdrawalAssetAddr) > 0) {
        _checkHealth(_provider, withdrawalAssetAddr, assetRate);
    }

    // Calculate receiving amount based on offer conditions
    uint256 receivingAmount = amountToSend != offer.withdrawalAsset.amount
        ? offer.depositAsset.unstandardize(
            offer.withdrawalAsset
                .standardize(amountToSend)
                .fullMulDiv(AssetHelper.BPS, offer.offer.offerPrice.unitPrice)
        )
        : offer.depositAsset.amount;

    // Require valid amount is received and deduct the fee inline
    require(receivingAmount > fee, "TZA");

    // Call external function at the end of state manipulations
    DOTCV2.takeOfferFixed(offerId, amountToSend, _provider);

    // Calculate and repay LZYBRA
    _repay(msg.sender, _provider, withdrawalAssetAddr,calc_share(amountToSend,withdrawalAssetAddr,msg.sender));

    // Update user balance in storage
    unchecked {
        UserAsset[_provider][withdrawalAssetAddr] = userAsset - amountToSend;
    }

    // Transfer remaining collateral minus fee
    collateralAsset.safeTransfer(_provider, receivingAmount - fee);

    // Emit event, calculating received amount inline
    emit WithdrawAsset(_provider, withdrawalAssetAddr, receivingAmount - fee);
}

function _withdrawTakeOfferDynamic(
    address _provider,
    uint256 offerId,
    uint256 amountToSend,
    uint256 maximumDepositToWithdrawalRate,
    address affiliate
) internal virtual {
    // Cache storage reads for optimal gas consumption
    DotcOffer memory offer = DOTCV2.allOffers(offerId);
    address withdrawalAssetAddr = offer.withdrawalAsset.assetAddress;
    uint256 userAsset = UserAsset[_provider][withdrawalAssetAddr];
    uint256 fee = feeStored[_provider];

    // Early reverts to save gas on failure paths
    require(offer.depositAsset.assetAddress == address(collateralAsset), "Withdraw Asset not USDC.");
    require(userAsset >= amountToSend && userAsset > 0, "Withdraw amount exceeds User Assets.");

    (uint256 assetRate, ) = getAssetPrice(offer.depositAsset, offer.withdrawalAsset, offer.offer.offerPrice);

    // Check health only if there are borrowed assets
    if (getBorrowed(_provider,withdrawalAssetAddr) > 0) {
        _checkHealth(_provider, withdrawalAssetAddr, assetRate);
    }

    // Call external function at the end of state manipulations
    DOTCV2.takeOfferDynamic(offerId, amountToSend,maximumDepositToWithdrawalRate, _provider);

 // Calculate receiving amount based on offer conditions
    DotcOffer memory new_offer = DOTCV2.allOffers(offerId);
    //USDC Asset
    uint256 receivingAmount = offer.depositAsset.amount - new_offer.depositAsset.amount;

    // Require valid amount is received and deduct the fee inline
    require(receivingAmount > fee, "TZA");

    // Calculate and repay LZYBRA
    _repay(msg.sender, _provider,withdrawalAssetAddr, calc_share(amountToSend,withdrawalAssetAddr,msg.sender));

    // Update user balance in storage
    unchecked {
        UserAsset[_provider][withdrawalAssetAddr] = userAsset - amountToSend;
    }

    // Transfer remaining collateral minus fee
    collateralAsset.safeTransfer(_provider, receivingAmount - fee);

    // Emit event, calculating received amount inline
    emit WithdrawAsset(_provider, withdrawalAssetAddr, receivingAmount - fee);

}
    /**
     * @dev Get USD value of current collateral asset and minted LZYBRA through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
     */
    function _checkHealth(address user, address asset , uint256 price) internal view {
        if (
            ((UserAsset[user][asset] * price * 100) / getBorrowed(user, asset)) <
            configurator.getSafeCollateralRatio(address(this)))
         
        revert("collateralRatio is Below safeCollateralRatio");
    }

    function _updateFee(address user, address asset) internal {
        if (block.timestamp > feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user, asset);
            feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(address user, address asset) internal view returns (uint256) {
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
    function getBorrowed(address user, address asset) public view returns (uint256) {
        return borrowed[user][asset] + feeStored[user] + _newFee(user,asset);
    }

    function getPoolTotalCirculation() external view returns (uint256) {
        return poolTotalCirculation;
    }




   function calc_share(uint256 amount, address asset, address user) internal view returns (uint256) {
    uint256 borrowedAmount = borrowed[user][asset];
    uint256 userAssetAmount = UserAsset[user][asset];
    require(userAssetAmount > 0, "UserAsset must be greater than zero");
    return (borrowedAmount * (amount / userAssetAmount));
}


    function getAssetPrice(Asset memory depositAsset,
        Asset memory withdrawalAsset,
        OfferPrice memory offerPrice) public view returns (uint256,uint256) {
        return AssetHelper.getRateAndPrice(
            depositAsset,
            withdrawalAsset,
            offerPrice
        );
    }

        function getAssetPriceOracle(address _asset) public view returns (uint256) {
        return AssetHelper.getRateAndPrice(
            depositAsset,
            withdrawalAsset,
            offerPrice
        );
    }
}
