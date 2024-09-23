// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Asset, AssetType, EscrowCallType, ValidityType, OfferStruct, DotcOffer} from "./structures/DotcStructuresV2.sol";
import "./interfaces/IERC7540.sol";

interface IPoolManager {
    function getTranchePrice(
        uint64 poolId,
        bytes16 trancheId,
        address asset
    ) external view returns (uint128 price, uint64 computedAt);
}

abstract contract ZybraVaultBase is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawAsset(
        address indexed sponsor,
        address asset,
        uint256 amount,
        uint256 timestamp
    );
    event Mint(address indexed sponsor, uint256 amount, uint256 timestamp);
    event Burn(
        address indexed sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );

    constructor(
        address _priceFeedAddress,
        address _collateralAsset,
        address _lzybra,
        address _dotcv2
    ) {
        LZYBRA = ILZYBRA(_lzybra);
        DOTCV2 = IDotcV2(_dotcv2);
        collateralAsset = IERC20(_collateralAsset);
    }

    function Deposit(
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

    

    function liquidation(
        address provider,
        address onBehalfOf,
        uint256 assetAmount
    ) external virtual {
        uint256 assetPrice = getCollateralAssetPrice();
        uint256 collateralRatio = (UserAsset[onBehalfOf][provider] * assetPrice * 100) / getBorrowed(onBehalfOf);

        require(collateralRatio < Iconfigurator(configurator).getBadCollateralRatio(address(this)), "Collateral ratio not low enough");

        require(assetAmount <= UserAsset[onBehalfOf][provider] / 2, "Cannot liquidate more than 50%");

        uint256 lzybraAmount = (assetAmount * assetPrice) / 1e18;
        _repay(provider, onBehalfOf, lzybraAmount);

        uint256 keeperReward = (assetAmount * Iconfigurator(configurator).vaultKeeperRatio(address(this))) / 100;
        uint256 finalAmount = assetAmount - keeperReward;

        collateralAsset.safeTransfer(msg.sender, keeperReward);
        collateralAsset.safeTransfer(provider, finalAmount);

        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            lzybraAmount,
            finalAmount,
            keeperReward,
            false,
            block.timestamp
        );
    }


      function _withdrawWithOffer(
        uint256 collat_amount,
        Asset calldata depositAsset,
        OfferStruct calldata offer
    ) internal virtual {
        // Cache storage reads to minimize gas consumption
        uint256 userAsset = UserAsset[_provider];
        uint256 userDepositedCollat = UserDepositedCollatAsset[_provider];
        uint256 fee = feeStored[_provider];

        // Use early revert patterns to save gas
        require(
            userAsset >= depositAsset.amount && userAsset != 0,
            "Withdraw amount exceeds deposited amount or low balance."
        );
       

        if (getBorrowed(_provider) > 0) {
            _checkHealth(
                _provider,
                getAssetPrice(depositAsset.assetAddress)
            );
        }
        Asset memory asset = Asset({
        assetType: AssetType.ERC20,
        assetAddress: USDC_ADDRESS,
        amount: collat_amount,
        reserved: 0
        });

        // Create the offer in DOTCV2
        DOTCV2.makeOffer(depositAsset, asset,offer);
        // Calculate the initial balance before offer is taken



        // Calculate the LZYBRA amount to repay
        uint256 lzybraAmount = calc_share(depositAsset.amount);

        // Repay the amount
        _repay(msg.sender, onBehalfOf, lzybraAmount);

        // Update user balances (minimizing storage writes by combining operations)
        UserAsset[_provider] = userAsset - depositAsset.amount;
        UserDepositedCollatAsset[_provider] =
            userDepositedCollat -
            receivedAmount;

        // Perform the transfer after all state changes

        // Emit the event at the end for gas efficiency
        emit WithdrawAsset(
            _provider,
            address(collateralAsset),
            receivedAmount,
            block.timestamp
        );
    }


    function _withdrawTakeOffer(
        address _provider,
        uint256 offerId,
        uint256 amountToSend
    ) internal virtual {
        // Cache storage reads to minimize gas consumption
        DotcOffer offer = DOTCV2.allOffers(offerId);
        uint256 userAsset = UserAsset[_provider][offer.depositAsset.assetAddress];
        uint256 fee = feeStored[_provider];

        // Use early revert patterns to save gas
        require(
            userAsset >= amountToSend && userAsset != 0,
            "Withdraw amount exceeds User Assets."
        );
               (uint256 assetRate, )=  getAssetPrice(offer.depositAsset,offer.withdrawalAsset,offer.offer);
    
        if (getBorrowed(_provider) > 0) {
            _checkHealth(
                _provider,
                assetRate
            );
        }


        // Execute the offer
        DOTCV2.takeOfferFixed( offerId,amountToSend, _provider);

        // Require a valid amount is received
        require(receivedAmount > 0, "TZA");

        // Calculate the LZYBRA amount to repay
        uint256 lzybraAmount = calc_share(amountToSend);

        // Repay the amount
        _repay(msg.sender, onBehalfOf, lzybraAmount);
    // remaining: Find out the price of the offer 
        // Update user balances (minimizing storage writes by combining operations)
        UserAsset[_provider][offer.depositAsset.assetAddress] = userAsset - amountToSend;

        // Perform the transfer after all state changes
        collateralAsset.safeTransfer(_provider, receivedAmount - fee);

        // Emit the event at the end for gas efficiency
        emit WithdrawAsset(
            _provider,
            address(collateralAsset),
            receivedAmount,
            block.timestamp
        );
    }


    function _mintLZYBRA(
        address _provider,
        uint256 _mintAmount,
        uint256 _assetPrice
    ) internal virtual {
        require(poolTotalCirculation + _mintAmount <= Iconfigurator(configurator).mintVaultMaxSupply(address(this)), "Max supply exceeded");
        _updateFee(_provider);

        borrowed[_provider] += _mintAmount;
        _checkHealth(_provider, _assetPrice);

        LZYBRA.mint(_provider, _mintAmount);
        poolTotalCirculation += _mintAmount;
        emit Mint(_provider, _mintAmount, block.timestamp);
    }

    function _repay(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal virtual {
        require(_amount <= borrowed[_onBehalfOf], "Amount exceeds borrowed");

        LZYBRA.transferFrom(_provider, address(this), _amount);
        LZYBRA.burn(_amount);

        borrowed[_onBehalfOf] -= _amount;
        poolTotalCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
    }

    function _checkHealth(address user, uint256 price) internal view {
        if (((UserAsset[user][address(collateralAsset)] * price * 100) / getBorrowed(user)) < Iconfigurator(configurator).getSafeCollateralRatio(address(this))) {
            revert("Collateral ratio is below safe limit");
        }
    }

    function _updateFee(address user) internal {
        if (block.timestamp > feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user);
            feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(address user) internal view returns (uint256) {
        return (borrowed[user] * Iconfigurator(configurator).vaultMintFeeApy(address(this)) * (block.timestamp - feeUpdatedAt[user])) / (86_400 * 365) / 10_000;
    }

    function getBorrowed(address user) public view returns (uint256) {
        return borrowed[user] + feeStored[user] + _newFee(user);
    }


    function getAssetPrice(
        Asset calldata depositAsset,
        Asset calldata withdrawalAsset,
        OfferPrice calldata offerPrice
    ) public view returns (uint256, uint256) {
       uint256 (depositToWithdrawalRate, withdrawalPrice) = AssetHelper.getRateAndPrice(depositAsset, withdrawalAsset, offerPrice);
        return (depositToWithdrawalRate, withdrawalPrice);
    }

    function calc_share(uint256 amount) public view returns (uint256) {
        return (borrowed[msg.sender] * amount) / UserAsset[msg.sender][address(collateralAsset)];
    }
}
