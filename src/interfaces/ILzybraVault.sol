// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "../structures/DotcStructuresV2.sol";
import "../interfaces/Iconfigurator.sol";
import "../interfaces/ILZYBRA.sol";
import "../interfaces/IDotcV2.sol";
import "../interfaces/AggregatorV2V3Interface.sol";

interface ILzybraVault {
    // Events
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
    event OfferClaimed(address indexed maker, uint256 offerId, address asset, uint256 amount);
    event repayDebt(address indexed sender, address indexed provider, address indexed asset, uint256 amount);

    // Structs
    struct Oracles {
        address chainlink;
        bytes32 pyth;
    }

    // Initialization
    function initialize(
        address _collateralAsset,
        address _lzybra,
        address _dotcv2,
        address _configurator,
        address _usdc_price_feed,
        address _pythAddress
    ) external;

    // Setters
    function setAssetOracles(
        address asset,
        bytes32 chainlinkOracle,
        bytes32 pythOracle
    ) external;

    // Public Views
    function getBorrowed(address user, address asset) external view returns (uint256);

    function getPoolTotalCirculation() external view returns (uint256);

    function getCollateralRatioAndLiquidationInfo(
        address user,
        address asset,
        bytes[] calldata priceUpdate
    ) external view returns (bool shouldLiquidate, uint256 collateralRatio);

    // User Actions
    function deposit(
        uint256 assetAmount,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer
    ) external;

    function deposit(
        uint256 assetAmount,
        uint256 offerId,
        uint256 mintAmount,
        bool isDynamic,
        uint256 maximumDepositToWithdrawalRate
    ) external;

    function withdraw(
        uint256 offerId,
        uint256 assetAmount,
        uint256 maximumDepositToWithdrawalRate,
        bool isDynamic,
        address affiliate
    ) external;

    function liquidation(
        address provider,
        address onBehalfOf,
        uint256 assetAmount,
        Asset calldata asset,
        bytes[] calldata priceUpdate
    ) external payable;

    function repayingDebt(
        address provider,
        address asset,
        uint256 lzybraAmount,
        bytes[] calldata priceUpdate
    ) external payable;

    function claimOffer(uint256 offerId) external;
}
