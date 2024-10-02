// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { AssetHelper } from "./helpers/AssetHelper.sol";
import {Asset, AssetType, OfferStruct,OfferPrice, DotcOffer} from "./structures/DotcStructuresV2.sol";
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
    IDotcV2 public DOTCV2;
    IERC20 public immutable collateralAsset;
    uint256 poolTotalCirculation;

    mapping(address => mapping(address => uint256)) public UserAsset; // User withdraw request tranche asset amount
    mapping(address => mapping(address => uint256)) borrowed;
    mapping(address => uint256) feeStored;
    mapping(address => uint256) feeUpdatedAt;
    mapping(address => bool) public vaultExists;

 
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
        address _initialOwner
    ) Ownable(_initialOwner){
        LZYBRA = ILZYBRA(_lzybra);
        DOTCV2 = IDotcV2(_dotcv2);
        collateralAsset = IERC20(_collateralAsset);
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
        Asset memory asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(collateralAsset),
            amount: assetAmount,
            reserved: 0
        });

        // Create the offer in DOTCV2
        DOTCV2.makeOffer(asset, withdrawalAsset, offer);

        // Fetch the price of the withdrawal asset and the exchange rate
        (uint256 depositToWithdrawalRate, ) = getAssetPrice(asset, withdrawalAsset, offer.offerPrice);

        // Mint LZYBRA tokens based on the asset price and deposit amount
        _mintLZYBRA(msg.sender, assetAmount, depositToWithdrawalRate);

        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount, block.timestamp);
    }


    function deposit(
        uint256 assetAmount,
        Asset calldata withdrawalAsset,
        uint256 offerId
    ) external virtual {
        require(assetAmount > 0, "Deposit amount must be greater than 0");

        // Transfer collateral to the contract
        collateralAsset.safeTransferFrom(msg.sender, address(this), assetAmount);

        // Approve the DOTC contract to handle the transferred amount
        collateralAsset.approve(address(DOTCV2), assetAmount);

        // Create an Asset struct for the deposit
        Asset memory asset = Asset({
            assetType: AssetType.ERC20,
            assetAddress: address(collateralAsset),
            amount: assetAmount,
            reserved: 0
        });

        // Create the offer in DOTCV2
        DOTCV2.takeOfferFixed(offerId, assetAmount, msg.sender);

        // Fetch the price of the withdrawal asset and the exchange rate
        // Fix offerId
        // (uint256 depositToWithdrawalRate, ) = getAssetPrice(asset, withdrawalAsset, offer.offerPrice);
uint256 depositToWithdrawalRate=0;
        // Mint LZYBRA tokens based on the asset price and deposit amount
        _mintLZYBRA(msg.sender, assetAmount, depositToWithdrawalRate);

        emit DepositAsset(msg.sender, address(collateralAsset), assetAmount, block.timestamp);
    }


    function mintLZYBRA(Asset memory withdrawalAsset , uint256 mintAmount) internal virtual {
        //fix 
        uint256 assetPrice = getAssetPrice(withdrawalAsset.assetAddress);
        _mintLZYBRA(msg.sender, msg.sender, mintAmount, assetPrice);
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

//     function liquidation(
//     address provider,
//     address onBehalfOf,
//     uint256 assetAmount,
//     Asset depositAsset
// ) external virtual {
//     // Fetch asset price and collateral ratio
//     uint256 assetPrice = getAssetPrice(withdrawalAsset.assetAddress);
//     uint256 depositAddress = depositAsset.assetAddress;

//     // Calculate collateral ratio
//     uint256 collateralValue = UserAsset[onBehalfOf][depositAddress] * assetPrice;
//     uint256 borrowedValue = getBorrowed(onBehalfOf);
//     uint256 onBehalfOfCollateralRatio = (collateralValue * 100) / borrowedValue;

//     // Check if collateral ratio falls below the badCollateralRatio threshold
//     // require(
//     //     onBehalfOfCollateralRatio < configurator.getBadCollateralRatio(address(this)),
//     //     "Borrower's collateral ratio should be below badCollateralRatio"
//     // );
//      require(
//         onBehalfOfCollateralRatio < 130e18,
//         "Borrower's collateral ratio should be below badCollateralRatio"
//     );

//     // Check if the provider is authorized to perform liquidation
//     require(
//         LZYBRA.allowance(provider, address(this)) != 0 || msg.sender == provider,
//         "Provider should authorize liquidation LZYBRA"
//     );

//     // Calculate LZYBRA amount to repay
//     uint256 LZYBRAAmount = (assetAmount * assetPrice) / 1e18;

//     // Redeem user's collateral and repay their debt
//     _repay(provider, onBehalfOf, calc_share(assetAmount, depositAddress, provider));

//     // Adjust the asset amount based on the collateral ratio
//     uint256 reducedAsset = assetAmount;
//     if (onBehalfOfCollateralRatio > 1e20 && onBehalfOfCollateralRatio < 11e19) {
//         reducedAsset = (assetAmount * onBehalfOfCollateralRatio) / 1e20;
//     }
//     if (onBehalfOfCollateralRatio >= 11e19) {
//         reducedAsset = (assetAmount * 11) / 10;
//     }

//     // Calculate rewards for the keeper (provider)
//     //config solve
//     // uint256 keeperRatio = configurator.vaultKeeperRatio(address(this));
//     uint256 keeperRatio = 110;
//     uint256 reward2keeper;
//     if (
//         msg.sender != provider && 
//         onBehalfOfCollateralRatio >= (1e20 + keeperRatio * 1e18)
//     ) {
//         reward2keeper = (assetAmount * keeperRatio) / 100;
//         collateralAsset.safeTransfer(msg.sender, reward2keeper); // Reward keeper
//     }

//     // Transfer the remaining reduced asset to the provider
//     collateralAsset.safeTransfer(provider, reducedAsset - reward2keeper);

//     // Emit liquidation event
//     emit LiquidationRecord(
//         provider,
//         msg.sender,
//         onBehalfOf,
//         LZYBRAAmount,
//         reducedAsset
//     );
// }


    /**
     * @dev Refresh LBR reward before adding providers debt. Refresh Zybra generated service fee before adding totalSupply. Check providers collateralRatio cannot below `safeCollateralRatio`after minting.
     */
    function _mintLZYBRA(
        address _provider,
        uint256 _mintAmount,
        uint256 _assetPrice
    ) internal virtual {
        // require(
        //     poolTotalCirculation + _mintAmount <=
        //         configurator.mintVaultMaxSupply(address(this)),
        //     "ESL"
        // );
        //configuration check
         require(
            poolTotalCirculation + _mintAmount <=
                12455,
            "ESL"
        );
        _updateFee(_provider);

        borrowed[_provider] += _mintAmount;
        _checkHealth(_provider, _assetPrice);

        LZYBRA.mint(_provider, _mintAmount);
        poolTotalCirculation += _mintAmount;
        emit Mint(_provider, _mintAmount, block.timestamp);
    }

    /**
     * @notice Burn _provideramount LZYBRA to payback minted LZYBRA for _onBehalfOf.
     *
     * @dev rePAY the User debt so the Collateral Ratio for user is mantained.
     */
    function _repay(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal virtual {
        require(_amount <= borrowed[_onBehalfOf], "Borrowed Amount is less");
        LZYBRA.transferFrom(msg.sender, address(this), _amount);
        LZYBRA.burn(_amount);
        borrowed[_onBehalfOf] -= _amount;
        poolTotalCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
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

    (uint256 assetRate, ) = getAssetPrice(offer.depositAsset, offer.withdrawalAsset, offer.offer);

    // Check health only if there are borrowed assets
    if (getBorrowed(_provider) > 0) {
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
    _repay(msg.sender, _provider, calc_share(amountToSend));

    // Update user balance in storage
    unchecked {
        UserAsset[_provider][withdrawalAssetAddr] = userAsset - amountToSend;
    }

    // Transfer remaining collateral minus fee
    collateralAsset.safeTransfer(_provider, receivingAmount - fee);

    // Emit event, calculating received amount inline
    emit WithdrawAsset(_provider, withdrawalAssetAddr, receivingAmount - fee, block.timestamp);
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

    (uint256 assetRate, ) = getAssetPrice(offer.depositAsset, offer.withdrawalAsset, offer.offer);

    // Check health only if there are borrowed assets
    if (getBorrowed(_provider) > 0) {
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
    _repay(msg.sender, _provider, calc_share(amountToSend));

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
            // ((UserAsset[user][asset] * price * 100) / getBorrowed(user)) <
            // configurator.getSafeCollateralRatio(address(this))
                       ((UserAsset[user][asset] * price * 100) / getBorrowed(user)) <
            18000)
         
        revert("collateralRatio is Below safeCollateralRatio");
    }

    function _updateFee(address user) internal {
        if (block.timestamp > feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user);
            feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(address user) internal view returns (uint256) {
        return
            (borrowed[user] *
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
    function getBorrowed(address user) public view returns (uint256) {
        return borrowed[user] + feeStored[user] + _newFee(user);
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


    function getAssetPrice(Asset calldata depositAsset,
        Asset calldata withdrawalAsset,
        OfferPrice calldata offerPrice) public view returns (uint256,uint256) {
        return AssetHelper.getRateAndPrice(
            depositAsset,
            withdrawalAsset,
            offerPrice
        );
    }
}
