// // SPDX-License-Identifier: BUSL-1.1

// pragma solidity ^0.8.20;

// import "./interfaces/Iconfigurator.sol";
// import "./interfaces/ILZYBRA.sol";
// import "./interfaces/IDotcV2.sol";
// import "./interfaces/AggregatorV2V3Interface.sol";
// import "../node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
// import "../node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
// import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
// import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
// import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
// import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
// import {AssetHelper} from "./helpers/AssetHelper.sol";
// import {Asset, AssetType, AssetPrice, OfferStruct, OfferPrice, DotcOffer, OfferFillType} from "./structures/DotcStructuresV2.sol";
// import {SafeTransferLib, FixedPointMathLib} from "./exports/ExternalExports.sol";
// import {OfferHelper} from "./helpers/OfferHelper.sol";
// import {IERC20} from "./interfaces/IERC20.sol";
// import {FeeLib,DecimalLib} from "./libraries/Zybralib.sol";


// contract ZybraVault is
//     Initializable,
//     UUPSUpgradeable,
//     OwnableUpgradeable,
//     ReentrancyGuardUpgradeable
// {
//     using FeeLib for *;
//     using DecimalLib for *;
//     using FixedPointMathLib for uint256;

//     using SafeTransferLib for address;
//     /// @dev Used for precise calculations.
//     /// @dev Used for Asset interaction.
//     using AssetHelper for Asset;

//     /// @dev Used for Offer interaction.
//     /// @dev Used for Dotc Offer interaction.

//     ILZYBRA public lzybra;
//     Iconfigurator public configurator;
//     IDotcV2 public dotv2;
//     IPyth public pyth;
//     AggregatorV2V3Interface internal _priceFeed;
//     IERC20 public usdc_collateralAsset;
//     uint256 public poolTotalCirculation;

//     struct Oracles {
//         address chainlink;
//         bytes32 pyth;
//     }

//     mapping(address => mapping(address => uint256)) public userAssets; // User withdraw request stock asset amount
//     mapping(address => mapping(address => uint256)) public borrowed;
//     mapping(uint256 => uint256) public depositAmounts;
//     mapping(uint256 => uint256) public WithdrawalAssetAmount;
//     mapping(address => uint256) public feeStored;
//     mapping(address => uint256) _feeUpdatedAt;
//     mapping(address => Oracles) public assetOracles;

//     // Existing events
//     event DepositAsset(
//         address indexed onBehalfOf,
//         address asset,
//         uint256 amount
//     );

//     event CancelDepositRequest(address indexed onBehalfOf, address asset);

//     event WithdrawAsset(address indexed sponsor, address asset, uint256 amount);

//     event LiquidationRecord(
//         address indexed provider,
//         address indexed keeper,
//         address indexed onBehalfOf,
//         uint256 LiquidateAssetAmount,
//         uint256 keeperReward
//     );

//     event OfferClaimed(
//         address indexed caller,
//         uint256 offerId,
//         address asset,
//         uint256 amount
//     );

//     event repayDebt(
//         address indexed sender,
//         address indexed provider,
//         address indexed asset,
//         uint256 amount
//     );

//     // Add new events for specific offer actions
//     event MakeWithdraw(address indexed sender, address asset, uint256 amount);

//     event DepositOfferClaimed(
//         address indexed caller,
//         uint256 offerId,
//         address indexed purchasedAsset,
//         uint256 amount
//     );

//     event WithdrawOfferClaimed(
//         address indexed caller,
//         uint256 offerId,
//         address indexed soldAsset,
//         uint256 amount
//     );

//     event OfferCancelled(
//         address indexed caller,
//         uint256 offerId,
//         uint256 depositAmount
//     );

//     modifier onlyExistingAsset(address _asset) {
//         Oracles memory oracles = assetOracles[_asset];
//         require(
//             oracles.chainlink != address(0) || oracles.pyth != bytes32(0),
//             "Asset not found in the oracles."
//         );
//         _;
//     }

//     /// @custom:oz-upgrades-unsafe-allow constructor
//     constructor() {
//         _disableInitializers();
//     }

//     function initialize(
//         address _collateralAsset,
//         address _lzybra,
//         address _dotcv2,
//         address _configurator,
//         address _usdc_price_feed,
//         bytes32 pyth_price_feed,
//         address _pythAddress
//     ) external initializer {
//         __Ownable_init();
//         __UUPSUpgradeable_init();

//         // Initialize state variables
//         usdc_collateralAsset = IERC20(_collateralAsset);
//         lzybra = ILZYBRA(_lzybra);
//         dotv2 = IDotcV2(_dotcv2);
//         configurator = Iconfigurator(_configurator);
//         assetOracles[_collateralAsset] = Oracles({
//             chainlink: _usdc_price_feed,
//             pyth: pyth_price_feed
//         });
//         pyth = IPyth(_pythAddress);

//         // Initialize mappings as needed
//         poolTotalCirculation = 0; // Defaults to 0, but explicitly set for clarity

//         // Initialize fees and other mappings
//         // Set default timestamps and fee storage
//         // _feeUpdatedAt and feeStored mappings will start with zero values
//     }

//     function _authorizeUpgrade(
//         address newImplementation
//     ) internal override onlyOwner {}

//     /**
//      * @notice Deposit USDC, update the interest distribution, can mint LZybra directly
//      * Emits a `DepositAsset` event.
//      *
//      * Requirements:
//      * - `assetAmount` Must be higher than 0.
//      * - `withdrawalAsset` withdrawal Asset details in Asset struct
//      * - `offer` offers details in OfferStruct struct
//      */
//     function deposit(
//         uint256 assetAmount,
//         Asset calldata withdrawalAsset,
//         OfferStruct calldata offer,
//         uint256 mintAmount
//     )
//         external
//         virtual
//         onlyExistingAsset(withdrawalAsset.assetAddress)
//         nonReentrant
//     {
//         require(assetAmount > 0, "Deposit amount must be greater than 0");

//         // Transfer collateral to the contract
//         usdc_collateralAsset.transferFrom(
//             msg.sender,
//             address(this),
//             assetAmount
//         );

//         // Approve DOTC contract only if needed
//         _approveIfNeeded(
//             address(usdc_collateralAsset),
//             address(dotv2),
//             assetAmount
//         );

//         // Create an Asset struct for the deposit
//         Asset memory usdc_asset = Asset({
//             assetType: AssetType.ERC20,
//             assetAddress: address(usdc_collateralAsset),
//             amount: assetAmount,
//             tokenId: 0,
//             assetPrice: AssetPrice(
//                 assetOracles[address(usdc_collateralAsset)].chainlink,
//                 0,
//                 0
//             )
//         });

//         // Create the offer in dotv2
//         dotv2.makeOffer(usdc_asset, withdrawalAsset, offer);
//         uint256 offerId = dotv2.currentOfferId();
//         depositAmounts[offerId] = assetAmount;
//         WithdrawalAssetAmount[offerId] = withdrawalAsset.amount;
//         userAssets[msg.sender][usdc_asset.assetAddress] += assetAmount;
//         uint256 depositToWithdrawalRate = _getFallbackPrice(
//             address(usdc_collateralAsset)
//         );
//         // uint256  depositToWithdrawalRate = 1e18;
//         // Mint lzybra tokens based on the asset price and deposit amount
//         _mintLZYBRA(
//             msg.sender,
//             mintAmount,
//             depositToWithdrawalRate,
//             usdc_asset.assetAddress
//         );

//         // Emit the DepositAsset event after state changes
//         emit DepositAsset(
//             msg.sender,
//             address(usdc_collateralAsset),
//             assetAmount
//         );
//     }

//     /**
//      * @notice Deposit USDC, update the interest distribution, can mint LZybra directly
//      * Emits a `DepositAsset` event.
//      *
//      * Requirements:
//      * - `assetAmount` Must be higher than 0.
//      * - `offerId` offerId representing the offer to takeOffer
//      * - `mintAmount` mint amount of lzybra
//      */

//     function deposit(
//         uint256 assetAmount,
//         uint256 offerId,
//         uint256 mintAmount,
//         bool isDynamic,
//         uint256 maximumDepositToWithdrawalRate
//     ) external virtual nonReentrant {
//         // Ensure asset amount is greater than zero
//         require(assetAmount > 0, "Deposit amount must be greater than 0");

//         // Get the offer and destructure it properly
//         (
//             ,
//             ,
//             Asset memory depositAsset,
//             Asset memory withdrawalAsset,
//             OfferStruct memory offerDetails
//         ) = dotv2.allOffers(offerId);

//         require(
//             depositAsset.assetAddress == address(usdc_collateralAsset),
//             "Asset must be USDC"
//         );
//         require(
//             assetOracles[withdrawalAsset.assetAddress].chainlink !=
//                 address(0) ||
//                 assetOracles[withdrawalAsset.assetAddress].pyth != bytes32(0),
//             "Asset not found in our oracle list."
//         );

//         // Transfer collateral to the contract
//         usdc_collateralAsset.transferFrom(
//             msg.sender,
//             address(this),
//             assetAmount
//         );

//         _approveIfNeeded(
//             address(usdc_collateralAsset),
//             address(dotv2),
//             assetAmount
//         );

//         uint256 depositToWithdrawalRate;
//         uint256 receivedWithdrawalAmount;

//         // Fetch the price of the withdrawal asset and the exchange rate
//         (depositToWithdrawalRate, ) = getAssetPrice(
//             Asset({
//                 assetType: AssetType.ERC20,
//                 assetAddress: address(usdc_collateralAsset),
//                 amount: assetAmount,
//                 tokenId: 0,
//                 assetPrice: AssetPrice(
//                     assetOracles[address(usdc_collateralAsset)].chainlink,
//                     0,
//                     0
//                 )
//             }),
//             withdrawalAsset,
//             offerDetails.offerPrice
//         );

//         if (isDynamic) {
//             // Dynamic Deposit Handling
//             dotv2.takeOfferDynamic(
//                 offerId,
//                 assetAmount,
//                 maximumDepositToWithdrawalRate,
//                 address(this)
//             );

//             // Fetch updated offer to get the remaining amount after deposit
//             (, , , Asset memory newWithdrawalAsset, ) = dotv2.allOffers(
//                 offerId
//             );
//             receivedWithdrawalAmount =
//                 newWithdrawalAsset.amount -
//                 withdrawalAsset.amount;
//         } else {
//             // Fixed Deposit Handling
//             dotv2.takeOfferFixed(offerId, assetAmount, address(this));

//             // Calculate received withdrawal amount based on fixed rate
//             receivedWithdrawalAmount = assetAmount.fullMulDiv(
//                 depositToWithdrawalRate,
//                 10 ** IERC20(withdrawalAsset.assetAddress).decimals()
//             );
//         }

//         // Update the user's asset balance in userAsset mapping
//         userAssets[msg.sender][
//             withdrawalAsset.assetAddress
//         ] += receivedWithdrawalAmount;

//         // Mint LZYBRA tokens based on the asset price and deposit amount
//         _mintLZYBRA(
//             msg.sender,
//             mintAmount,
//             depositToWithdrawalRate,
//             withdrawalAsset.assetAddress
//         );

//         // Emit deposit event with relevant details
//         emit DepositAsset(
//             msg.sender,
//             address(usdc_collateralAsset),
//             assetAmount
//         );
//     }

//     /**
//      * @notice Withdraw collateral assets to an address
//      * Emits a `WithdrawAsset` event.
//      *
//      * Requirements:
//      * - `offerId` cannot be the zero address.
//      * - `asset_amount` Must be higher than 0.
     
//      * @dev Withdraw collateral. Check user’s collateral ratio after withdrawal, should be higher than `safeCollateralRatio`
//      */

//     function withdraw(
//         uint256 assetAmount,
//         Asset calldata depositAsset,
//         OfferStruct calldata offer
//     ) external virtual nonReentrant {
//         require(assetAmount > 0, "ZA");
//         // Transfer collateral to the contract
//         uint256 userAsset = userAssets[msg.sender][depositAsset.assetAddress];

//         // Ensure user has enough assets to withdraw
//         require(userAsset >= assetAmount, "AX");

//         _approveIfNeeded(
//             address(depositAsset.assetAddress),
//             address(dotv2),
//             assetAmount
//         );

//         // Create an Asset struct for the deposit
//         Asset memory usdc_asset = Asset({
//             assetType: AssetType.ERC20,
//             assetAddress: address(usdc_collateralAsset),
//             amount: assetAmount,
//             tokenId: 0,
//             assetPrice: AssetPrice(
//                 assetOracles[address(usdc_collateralAsset)].chainlink,
//                 0,
//                 0
//             )
//         });

//         // Create the offer in dotv2
//         dotv2.makeOffer(depositAsset, usdc_asset, offer);
//         uint256 offerId = dotv2.currentOfferId();
//         WithdrawalAssetAmount[offerId] = assetAmount;
//         depositAmounts[offerId] = depositAsset.amount;

//         // Emit withdrawal event with net amount received
//         emit MakeWithdraw(msg.sender, depositAsset.assetAddress, assetAmount);
//     }

//     /**
//      * @notice Withdraw collateral assets to an address
//      * Emits a `WithdrawAsset` event.
//      *
//      * Requirements:
//      * - `offerId` cannot be the zero address.
//      * - `asset_amount` Must be higher than 0.
     
//      * @dev Withdraw collateral. Check user’s collateral ratio after withdrawal, should be higher than `safeCollateralRatio`
//      */

//     function withdraw(
//         uint256 offerId,
//         uint256 assetAmount,
//         uint256 burnAmount,
//         uint256 maximumDepositToWithdrawalRate,
//         bool isDynamic,
//         address affiliate
//     ) external virtual nonReentrant {
//         require(assetAmount > 0, "ZA");

//         // Get the offer and destructure it properly
//         (
//             ,
//             ,
//             Asset memory depositAsset,
//             Asset memory withdrawalAsset,
//             OfferStruct memory offerDetails
//         ) = dotv2.allOffers(offerId);

//         address depositAssetAddr = depositAsset.assetAddress;
//         uint256 userAsset = userAssets[msg.sender][depositAssetAddr];

//         // Ensure user has enough assets to withdraw
//         require(userAsset >= assetAmount, "AX.");
//         require(depositAssetAddr == address(usdc_collateralAsset), "AA.");

//         // Approve DOTC contract only if needed
//         _approveIfNeeded(depositAssetAddr, address(dotv2), assetAmount);

//         (uint256 assetRate, ) = getAssetPrice(
//             depositAsset,
//             withdrawalAsset,
//             offerDetails.offerPrice
//         );

//         // Check health only if there are borrowed assets
//         if (getBorrowed(msg.sender, depositAssetAddr) > 0) {
//             _checkHealth(msg.sender, depositAssetAddr, assetRate);
//         }

//         uint256 receivingAmount;
//         if (isDynamic) {
//             // Dynamic Offer Withdrawal
//             dotv2.takeOfferDynamic(
//                 offerId,
//                 assetAmount,
//                 maximumDepositToWithdrawalRate,
//                 msg.sender
//             );

//             // Get updated offer state
//             (, , Asset memory newDepositAsset, , ) = dotv2.allOffers(offerId);
//             receivingAmount = depositAsset.amount - newDepositAsset.amount;
//         } else {
//             // Fixed Offer Withdrawal
//             dotv2.takeOfferFixed(offerId, assetAmount, msg.sender);
//             receivingAmount = assetAmount != withdrawalAsset.amount
//                 ? depositAsset.unstandardize(
//                     withdrawalAsset.standardize(assetAmount).fullMulDiv(
//                         AssetHelper.BPS,
//                         offerDetails.offerPrice.unitPrice
//                     )
//                 )
//                 : depositAsset.amount;
//         }

//         // Calculate and subtract fees, ensuring valid amount is received
//         uint256 fee = feeStored[msg.sender];
//         require(receivingAmount > fee, "TZA");
//         receivingAmount -= fee;

//         // Calculate and repay lzybra based on user's share
//         _repay(msg.sender, msg.sender, depositAssetAddr, burnAmount);

//         // Update user balance in storage
//         unchecked {
//             userAssets[msg.sender][depositAssetAddr] = userAsset - assetAmount;
//         }

//         // Transfer remaining collateral after fee deduction
//         usdc_collateralAsset.transfer(msg.sender, receivingAmount);

//         // Emit withdrawal event with net amount received
//         emit WithdrawAsset(msg.sender, depositAssetAddr, receivingAmount);
//     }

//     /**
//      * @notice Keeper liquidates borrowers whose collateral ratio is below badCollateralRatio, using lzybra provided by Liquidation Provider.
//      *
//      * Requirements:
//      * - provider should authorize Zybra to utilize lzybra
//      * - onBehalfOf Collateral Ratio should be below badCollateralRatio
//      * - assetAmount should be less than 50% of collateral
//      * - asset Asset to be Liquidated
//      * - priceUpdate priceUpdate comes from Hermes Api to get token price from Pyth Oracle  
     
//      * @dev After liquidation, borrower's debt is reduced by assetAmount * AssetPrice, providers and keepers can receive up to an additional 10% liquidation reward.
//      */

//     function liquidation(
//         address provider,
//         address onBehalfOf,
//         uint256 assetAmount,
//         Asset calldata asset,
//         bytes[] calldata priceUpdate
//     ) external payable nonReentrant {
//         // Input Validation
//         require(asset.assetAddress != address(0), "Invalid asset address");
//         require(assetAmount > 0, "Asset amount must be greater than 0");
//         require(onBehalfOf != address(0), "Invalid onBehalfOf address");
//         require(provider != address(0), "Invalid provider address");

//         // Fetch collateral ratio and validate liquidation threshold
//         address tAddress = asset.assetAddress;
//         (
//             bool shouldLiquidate,
//             uint256 collateralRatio,
//             uint256 assetPrice
//         ) = getCollateralRatioAndLiquidationInfo(
//                 onBehalfOf,
//                 tAddress,
//                 priceUpdate
//             );
//         require(shouldLiquidate, "Above liquidation threshold");

//         // Ensure liquidation amount does not exceed 50% of collateral
//         uint256 maxLiquidationAmount = userAssets[onBehalfOf][tAddress] / 2;
//         require(assetAmount <= maxLiquidationAmount, "Max 50% collateral");

//         // Stricter Authorization Check
//         require(
//             msg.sender == provider ||
//                 lzybra.allowance(provider, address(this)) >= assetAmount,
//             "Provider must authorize"
//         );

//         // Calculate Zrusd amount with higher precision
//         uint256 lzybraAmount = assetAmount.fullMulDiv(assetPrice, 1e18);

//         // Initialize variables
//         uint256 keeperReward = 0;
//         uint256 reducedAsset = assetAmount;

//         // Adjust reducedAsset and calculate keeper reward if collateral ratio is above threshold
//         if (collateralRatio > 1e20) {
//             reducedAsset = (collateralRatio < 11e19)
//                 ? (assetAmount * collateralRatio) / 1e20
//                 : (assetAmount * 11) / 10;

//             // Calculate keeper reward if applicable
//             uint256 keeperRatio = configurator.vaultKeeperRatio(address(this));
//             if (
//                 msg.sender != provider &&
//                 collateralRatio >= 1e20 + keeperRatio * 1e18
//             ) {
//                 keeperReward = assetAmount.fullMulDiv(keeperRatio, 100);
//                 require(
//                     keeperReward <= reducedAsset,
//                     "Keeper reward exceeds reduced asset"
//                 );

//                 // Transfer keeper reward
//                 IERC20(tAddress).transfer(msg.sender, keeperReward);
//             }
//         }

//         // Repay debt and adjust balances
//         _repay(provider, onBehalfOf, tAddress, lzybraAmount);

//         // Transfer remaining assets to provider
//         uint256 providerAmount = reducedAsset - keeperReward;
//         IERC20(tAddress).transfer(provider, providerAmount);

//         // Adjust userAsset storage in a single update
//         userAssets[onBehalfOf][tAddress] -= reducedAsset + keeperReward;

//         // Emit events for critical actions
//         emit LiquidationRecord(
//             provider,
//             msg.sender,
//             onBehalfOf,
//             lzybraAmount,
//             reducedAsset
//         );
//     }

//     function repayingDebt(
//         address provider,
//         address asset,
//         uint256 lzybraAmount,
//         bytes[] calldata priceUpdate
//     ) external payable virtual {
//         require(
//             borrowed[asset][provider] >= lzybraAmount,
//             "lzybraAmount cannot surpass providers debt"
//         );
//         (
//             ,
//             uint256 providerCollateralRatio,

//         ) = getCollateralRatioAndLiquidationInfo(provider, asset, priceUpdate);

//         // Ensure the collateral ratio is healthy (at least 100%) for debt repayment
//         require(
//             providerCollateralRatio >=
//                 configurator.getSafeCollateralRatio(address(this))
//         );
//         _repay(provider, asset, provider, lzybraAmount);
//         emit repayDebt(msg.sender, provider, asset, lzybraAmount);
//     }

//     function claimOffer(
//         uint256 offerId,
//         uint256 lzybraDebt,
//         bytes[] calldata priceUpdate
//     ) external nonReentrant {
//         // Get the offer and destructure it properly
//         (
//             address maker,
//             OfferFillType offerFillType,
//             Asset memory depositAsset,
//             Asset memory withdrawalAsset,
//         ) = dotv2.allOffers(offerId);

//         if (
//             maker == address(0) ||
//             maker != msg.sender ||
//             offerFillType != OfferFillType.FullyTaken
//         ) revert("IF");

//         address caller = msg.sender;
//         address usdcAddress = address(usdc_collateralAsset);
//         uint256 amount = WithdrawalAssetAmount[offerId];
//         uint256 originalDepositAmount = depositAmounts[offerId];

//         if (amount == 0 || originalDepositAmount == 0) revert("IM");

//         bool isDeposit = depositAsset.assetAddress == usdcAddress;

//         if (isDeposit) {
//             // USDC -> Other Asset
//             address purchasedAsset = withdrawalAsset.assetAddress;
//             if (originalDepositAmount == 0) revert("ID");

//             uint256 totalUserUSDC = userAssets[caller][usdcAddress];
//             if (totalUserUSDC < originalDepositAmount) revert("IB");

//             unchecked {
//                 userAssets[caller][usdcAddress] =
//                     totalUserUSDC -
//                     originalDepositAmount;
//                 userAssets[caller][purchasedAsset] += amount;
//             }

//             _updateFee(caller, purchasedAsset);

//             uint256 currentDebt = borrowed[caller][usdcAddress];
//             if (currentDebt > 0) {
//                 uint256 offerDebtShare;
//                 assembly {
//                     offerDebtShare := div(
//                         mul(currentDebt, originalDepositAmount),
//                         totalUserUSDC
//                     )
//                 }

//                 unchecked {
//                     borrowed[caller][purchasedAsset] += offerDebtShare;
//                     borrowed[caller][usdcAddress] =
//                         currentDebt -
//                         offerDebtShare;
//                 }
//             }

//             emit DepositOfferClaimed(caller, offerId, purchasedAsset, amount);
//         } else {
//             // Other Asset -> USDC
//             address soldAsset = depositAsset.assetAddress;

//             unchecked {
//                 userAssets[caller][soldAsset] -= amount;
//             }
//             _repay(caller, caller, soldAsset, lzybraDebt);
//             _checkHealth(
//                 msg.sender,
//                 soldAsset,
//                 getAssetPriceOracle(soldAsset, priceUpdate)
//             );
//             usdc_collateralAsset.transfer(caller, amount);

//             emit WithdrawOfferClaimed(caller, offerId, soldAsset, amount);
//         }

//       assembly {
//             mstore(0x00, offerId)
//             mstore(0x20, depositAmounts.slot)
//             let depositMapSlot := keccak256(0x00, 0x40)

//             mstore(0x00, offerId)
//             mstore(0x20, WithdrawalAssetAmount.slot)
//             let withdrawalMapSlot := keccak256(0x00, 0x40)

//             sstore(depositMapSlot, 0)
//             sstore(withdrawalMapSlot, 0)
//         }
//     }

//     function cancelOffer(
//         uint256 offerId,
//         uint256 lzybraDebt
//     ) external nonReentrant {
//         // Get the offer and destructure it properly
//         (
//             address maker,
//             OfferFillType offerFillType,
//             Asset memory depositAsset,
//             Asset memory withdrawalAsset,
//         ) = dotv2.allOffers(offerId);

//         if (
//             maker == address(0) ||
//             maker != msg.sender ||
//             offerFillType == OfferFillType.FullyTaken ||
//             offerFillType == OfferFillType.Cancelled
//         ) revert("IF");

//         address caller = msg.sender;
//         address usdcAddress = address(usdc_collateralAsset);

//         bool isDeposit = depositAsset.assetAddress == usdcAddress;
//         uint256 depositAmount = depositAmounts[offerId];

//         if (depositAmount == 0) revert("IDA");

//         if (isDeposit) {
//             // Only handle debt if there was any borrowing for this offer
//             uint256 currentDebt = borrowed[caller][usdcAddress];
//             if (currentDebt >= lzybraDebt && lzybraDebt > 0)
//                 _repay(caller, caller, usdcAddress, lzybraDebt);
//             // Only repay if there's actual debt for this offer
//             unchecked {
//                 userAssets[caller][usdcAddress] -= depositAmount;
//             }
//             // Return USDC directly to user
//             usdc_collateralAsset.transfer(caller, depositAmount);
//         } else {
//             unchecked {
//                 userAssets[caller][
//                     withdrawalAsset.assetAddress
//                 ] -= depositAmount;
//             }
//             // Return asset
//             IERC20(withdrawalAsset.assetAddress).transfer(
//                 caller,
//                 depositAmount
//             );
//         }

//         // Cancel offer in DOTCV2
//         dotv2.cancelOffer(offerId);

//         // Clear storage for specific offerId
//        assembly {
//             mstore(0x00, offerId)
//             mstore(0x20, depositAmounts.slot)
//             let depositMapSlot := keccak256(0x00, 0x40)

//             mstore(0x00, offerId)
//             mstore(0x20, WithdrawalAssetAmount.slot)
//             let withdrawalMapSlot := keccak256(0x00, 0x40)

//             sstore(depositMapSlot, 0)
//             sstore(withdrawalMapSlot, 0)
//         }


//         emit OfferCancelled(caller, offerId, depositAmount);
//     }

//     /**
//      * @dev Refresh LBR reward before adding providers debt. Refresh Zybra generated service fee before adding totalSupply. Check providers collateralRatio cannot below `safeCollateralRatio`after minting.
//      */
//     function _mintLZYBRA(
//         address _provider,
//         uint256 _mintAmount,
//         uint256 _assetPrice,
//         address asset
//     ) internal virtual {
//         require(
//             poolTotalCirculation + _mintAmount <=
//                 configurator.mintVaultMaxSupply(address(this)),
//             "ESL"
//         );

//         _updateFee(_provider, asset);
//         borrowed[_provider][asset] += _mintAmount;
//         _checkHealth(_provider, asset, _assetPrice);

//         lzybra.mint(_provider, _mintAmount);
//         poolTotalCirculation += _mintAmount;
//     }

//     /**
//      * @notice Burn _provideramount lzybra to payback minted lzybra for _onBehalfOf.
//      *
//      * @dev rePAY the User debt so the Collateral Ratio for user is mantained.
//      */
//     function _repay(
//         address _provider,
//         address _onBehalfOf,
//         address asset,
//         uint256 _amount
//     ) internal virtual {
//         _updateFee(_onBehalfOf, asset);
//         lzybra.transferFrom(_provider, address(this), _amount);
//         lzybra.burn(_provider, _amount);
//         borrowed[_onBehalfOf][asset] -= _amount;
//         poolTotalCirculation -= _amount;
//     }

//     function setAssetOracles(
//         address asset,
//         address chainlinkOracle,
//         bytes32 pythOracle
//     ) external {
//         require(
//             chainlinkOracle != address(0) || pythOracle != bytes32(0),
//             "At least one oracle must be set"
//         );

//         assetOracles[asset] = Oracles({
//             chainlink: chainlinkOracle,
//             pyth: pythOracle
//         });
//     }

//     /**
//      * @dev Get USD value of current collateral asset and minted lzybra through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
//      */
//     function _checkHealth(
//         address user,
//         address asset,
//         uint256 price
//     ) internal view {
//         if (
//             ((userAssets[user][asset] * price * 100) /
//                 getBorrowed(user, asset)) <
//             configurator.getSafeCollateralRatio(address(this))
//         ) revert("collateralRatio is Below safeCollateralRatio");
//     }

 

//     function _updateFee(address user, address asset) internal {
//         FeeLib.updateFee(
//             user,
//             asset,
//             borrowed[user][asset],
//             _feeUpdatedAt,
//             feeStored
//         );

//     }

//     function _newFee(
//         address user,
//         address asset
//     ) internal view returns (uint256) {
//         return
//             borrowed[user][asset].fullMulDiv(86_400, 365).fullMulDiv(
//                 100,
//                 10_000
//             );
//     }

//     /**
//      * @dev Approve tokens only if allowance is insufficient.
//      */
//     function _approveIfNeeded(
//         address asset,
//         address spender,
//         uint256 amount
//     ) internal {
//         uint256 currentAllowance = IERC20(asset).allowance(
//             address(this),
//             spender
//         );
//         if (currentAllowance < amount) {
//             bool success = IERC20(asset).approve(
//                 spender,
//                 (amount - currentAllowance) * 20
//             );
//             require(success, "Approval failed");
//         }
//     }

//     /**
//      * @dev Returns the current borrowing amount for the user, including borrowed shares and accumulated fees.
//      * @param user The address of the user.
//      * @return The total borrowing amount for the user.
//      */
//     function getBorrowed(
//         address user,
//         address asset
//     ) public view returns (uint256) {
//         return borrowed[user][asset];
//     }

//     function getPoolTotalCirculation() external view returns (uint256) {
//         return poolTotalCirculation;
//     }

//     function _calcShare(
//         uint256 amount,
//         address asset,
//         address user
//     ) internal view returns (uint256) {
//         uint256 borrowedAmount = borrowed[user][asset];
//         uint256 userAssetAmount = userAssets[user][asset];
//         require(userAssetAmount > 0, "userAsset must be greater than zero");

//         // Calculate share with multiplication before division to maintain precision
//         return borrowedAmount.fullMulDiv(amount, userAssetAmount);
//     }

//     function getCollateralRatioAndLiquidationInfo(
//         address user,
//         address asset,
//         bytes[] calldata priceUpdate
//     )
//         public
//         returns (
//             bool shouldLiquidate,
//             uint256 collateralRatio,
//             uint256 assetPrice
//         )
//     {
//         // Get the user's asset amount and the current price of the asset
//         uint256 userCollateralAmount = userAssets[user][asset];
//         assetPrice = getAssetPriceOracle(asset, priceUpdate);

//         // Calculate the USD value of the collateral
//         uint256 collateralValueInUSD = (userCollateralAmount * assetPrice) /
//             1e18;

//         // Get the user's total borrowed amount in LZYBRA (assumed to be in USD)
//         uint256 userDebtAmount = getBorrowed(user, asset);

//         // Avoid division by zero: if the user has no debt, return max collateral ratio and no liquidation
//         if (userDebtAmount == 0) {
//             return (false, type(uint256).max, assetPrice); // No liquidation if no debt, max ratio
//         }

//         // Calculate the collateral ratio
//         collateralRatio =
//             ((collateralValueInUSD * 1e18) / userDebtAmount) *
//             100;

//         // Determine if the collateral ratio falls below the liquidation threshold
//         uint256 badCollateralRatio = configurator.getBadCollateralRatio(
//             address(this)
//         );
//         shouldLiquidate = collateralRatio < badCollateralRatio;
//     }

//     function getAssetPrice(
//         Asset memory depositAsset,
//         Asset memory withdrawalAsset,
//         OfferPrice memory offerPrice
//     ) internal view returns (uint256, uint256) {
//         return
//             AssetHelper.getRateAndPrice(
//                 depositAsset,
//                 withdrawalAsset,
//                 offerPrice
//             );
//     }

//     function getAssetPriceOracle(
//         address _asset,
//         bytes[] calldata priceUpdate
//     ) public payable returns (uint256) {
//         Oracles memory oracles = assetOracles[_asset];

//         // Validate that the asset has at least one oracle set
//         require(
//             oracles.chainlink != address(0) || oracles.pyth != bytes32(0),
//             "No oracles available for this asset."
//         );

//         uint256 fee;

//         // Attempt to update the Pyth price feed if a Pyth oracle is set
//         if (oracles.pyth != bytes32(0)) {
//             // Calculate the fee required to update the price
//             fee = pyth.getUpdateFee(priceUpdate);

//             // Update the price feeds - Pyth's contract will verify signatures internally
//             try pyth.updatePriceFeeds{value: fee}(priceUpdate) {
//                 // No additional signature check needed since Pyth already performs this
//             } catch {
//                 revert("Invalid or tampered Pyth price update.");
//             }

//             int64 priceInt;

//             // Attempt to get the primary price feed from Pyth (Pyth returns prices with 8 decimals)
//             try pyth.getPriceNoOlderThan(oracles.pyth, 60) returns (
//                 PythStructs.Price memory priceData
//             ) {
//                 priceInt = priceData.price;
//             } catch {
//                 // If Pyth fails, attempt to get the Chainlink price
//                 return _getFallbackPrice(_asset);
//             }

//             // Ensure the price is non-negative
//             require(priceInt > 0, "Pyth price cannot be negative.");

//             // Pyth returns prices with 8 decimals, scale to 18 decimals
//             uint256 scaledPrice = DecimalLib.convertDecimals(
//                 uint256(int256(priceInt)),
//                 8,
//                 18
//             );

//             return scaledPrice; // Return the price in 18 decimals
//         }

//         // If no Pyth oracle is set, use the Chainlink fallback directly
//         return _getFallbackPrice(_asset);
//     }

//     // Fallback price function for Chainlink (already 8 decimals)
//     function _getFallbackPrice(address _asset) internal view returns (uint256) {
//         Oracles memory oracles = assetOracles[_asset];

//         // Validate that a Chainlink oracle is set for the asset
//         require(
//             oracles.chainlink != address(0),
//             "No Chainlink oracle available for this asset."
//         );

//         // Fetch the latest price from Chainlink
//         (, int256 price, , , ) = AggregatorV2V3Interface(oracles.chainlink)
//             .latestRoundData();

//         // Ensure the price is non-negative
//         require(price >= 0, "Chainlink price feed returned a negative value.");

//         // Chainlink returns prices with 8 decimals, scale to 18 decimals
//         return DecimalLib.convertDecimals(uint256(price), 8, 18);
//     }
// }
