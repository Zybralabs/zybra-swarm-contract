// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./Iconfigurator.sol";
import "./ILZYBRA.sol";
import "./IDotcV2.sol";
import "./AggregatorV2V3Interface.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Asset, AssetType, OfferStruct, OfferPrice, DotcOffer} from "./structures/DotcStructuresV2.sol";



    // Events
    event DepositAsset(address indexed onBehalfOf, address asset, uint256 amount);
    event CancelDepositRequest(address indexed onBehalfOf, address asset);
    event WithdrawAsset(address indexed sponsor, address asset, uint256 amount);
    event Mint(address indexed sponsor, uint256 amount);
    event Burn(address indexed sponsor, address indexed onBehalfOf, uint256 amount);
    event LiquidationRecord(
        address indexed provider,
        address indexed keeper,
        address indexed onBehalfOf,
        uint256 LiquidateAssetAmount,
        uint256 keeperReward
    );

    // Functions
    function initialize(
        address _collateralAsset,
        address _lzybra,
        address _dotcv2,
        address _configurator,
        address _usdc_price_feed,
        address _pythAddress
    ) external;

    function deposit(
        uint256 assetAmount,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer
    ) external;

    function deposit(
        uint256 assetAmount,
        uint256 offerId,
        uint256 mintAmount
    ) external;

    function withdraw(uint256 offerId, uint256 asset_amount) external;

    function withdraw(
        uint256 offerId,
        uint256 maximumDepositToWithdrawalRate,
        uint256 asset_amount
    ) external;

    function liquidation(
        address provider,
        address onBehalfOf,
        uint256 assetAmount,
        Asset calldata asset,
        bytes[] calldata priceUpdate
    ) external payable;

    function addPriceFeed(
        address _asset,
        bytes32 pythPriceId,
        address chainlinkAggregator
    ) external;

    function claimOffer(uint256 offerId) external;

    // View and Getter Functions
    function getBorrowed(address user, address asset) external view returns (uint256);

    function getPoolTotalCirculation() external view returns (uint256);

    function calc_share(
        uint256 amount,
        address asset,
        address user
    ) external view returns (uint256);

    function getAssetPrice(
        Asset memory depositAsset,
        Asset memory withdrawalAsset,
        OfferPrice memory offerPrice
    ) external view returns (uint256, uint256);

    function getAssetPriceOracle(
        address _asset,
        bytes[] calldata priceUpdate
    ) external payable returns (uint256);

    function getFallbackPrice(address _asset) external view returns (uint256);
}
