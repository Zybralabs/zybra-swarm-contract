// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./interfaces/Iconfigurator.sol";
import "./interfaces/ILZYBRA.sol";
import "./interfaces/IDotcV2.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { Asset, AssetType, EscrowCallType, ValidityType, OfferStruct, DotcOffer } from "./structures/DotcStructuresV2.sol";

import "./interfaces/IERC7540.sol";

interface IPoolManager {
    function getTranchePrice(
        uint64 poolId,
        bytes16 trancheId,
        address asset
    ) external view returns (uint128 price, uint64 computedAt);
}

abstract contract ZybraVaultBase is Ownable , ReentrancyGuard{
    using SafeERC20 for IERC20;
    ILZYBRA public immutable LZYBRA;
    AggregatorV3Interface public immutable priceFeed;
    IERC20 public immutable collateralAsset;
    uint256 poolTotalCirculation;

    mapping(address => mapping(address => uint256))
        public UserDepositedCollatAsset;
    mapping(address => mapping(address => uint256))
        public UserDepReqVaultCollatAsset;
    mapping(address => mapping(address => uint256))
        public UserWithdReqVaultTrancheAsset; // User withdraw request tranche asset amount
    mapping(address => mapping(address => uint256))
        public UserAsset; // User withdraw request tranche asset amount
    mapping(address => mapping(address => uint256)) borrowed;
    mapping(address => uint256) feeStored;
    mapping(address => uint256) feeUpdatedAt;
    mapping(address => bool) public vaultExists;

    event DepositEther(
        address indexed onBehalfOf,
        address asset,
        uint256 etherAmount,
        uint256 assetAmount,
        uint256 timestamp
    );
    event RequestDepositAsset(
        address indexed onBehalfOf,
        address asset,
        
        uint256 amount,
        uint256 timestamp
    );
    event DepositAsset(
        address indexed onBehalfOf,
        address asset,
        
        uint256 amount,
        uint256 timestamp
    );
    event CancelDepositRequest(
        address indexed onBehalfOf,
        address asset,
        
        uint256 timestamp
    );
    event CancelWithdrawRequest(
        address indexed onBehalfOf,
        address asset,
        
        uint256 amount,
        uint256 timestamp
    );
    event RequestWithdrawAsset(
        address indexed sponsor,
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
    event Mint(
        address indexed sponsor,
        uint256 amount,
        uint256 timestamp
    );
    event Burn(
        address indexed sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event LiquidationRecord(
        address indexed provider,
        address indexed keeper,
        address indexed onBehalfOf,
        uint256 eusdamount,
        uint256 LiquidateAssetAmount,
        uint256 keeperReward,
        bool superLiquidation,
        uint256 timestamp
    );

    event RigidRedemption(
        address indexed caller,
        address indexed provider,
        
        uint256 LZYBRAAmount,
        uint256 assetAmount,
        uint256 timestamp
    );
    event FeeDistribution(
        address indexed feeAddress,
        uint256 feeAmount,
        uint256 timestamp
    );

    modifier onlyExistingVault() {
        require(vaultExists[_vault], "Vault does not exist");
        _;
    }

    constructor(
        address _priceFeedAddress,
        address _collateralAsset,
        address _lzybra,
        address _dotcv2
    ) {
        LZYBRA = ILZYBRA(_lzybra);
        DOTCV2 = IDOTCV2(_dotcv2);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
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
    function Deposit(
        uint256 assetAmount,
        Asset calldata withdrawalAsset,
        OfferStruct calldata offer
    ) external virtual  {
        require(assetAmount >= 0, "Deposit should not be less than 0");

        collateralAsset.safeTransferFrom(
            msg.sender,
            address(this),
            assetAmount
        );
        
        collateralAsset.approve(_vault, assetAmount);
        Asset = new Asset(AssetType.ERC20,USDC_ADDRESS, assetAmount,0);
        DOTCv2.makeOffer(Asset, msg.sender, address(this));
        UserDepositedCollatAsset[_vault][msg.sender] += assetAmount;
        uint256 assetPrice = getAssetPrice(withdrawalAsset.assetAddress);
        _mintLZYBRA(msg.sender, msg.sender, mintAmount, assetPrice);

        emit DepositAsset(
            msg.sender,
            address(collateralAsset),
            _vault,
            assetAmount,
            block.timestamp
        );
    }

 
  

    function mintLZYBRA(
        uint256 mintAmount,
        
    ) external virtual onlyExistingVault(_vault){

        uint256 assetPrice = getAssetPrice(withdrawalAsset.assetAddress);
        _mintLZYBRA(msg.sender, _vault, msg.sender, mintAmount, assetPrice);

    }
    function setEndorsedOperator(
        address owner,
        bool approved,
        
    ) external virtual onlyExistingVault(_vault) {
        
        DOTCv2.setEndorsedOperator(msg.sender, true);
    }

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawAsset` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `tranche_amount` Must be higher than 0.
     * - `_vault` address of the Centrifuge Vault.
     * @dev Withdraw collateral. Check user’s collateral ratio after withdrawal, should be higher than `safeCollateralRatio`
     */
    function withdraw(
        
        uint256 tranche_amount
    ) external virtual onlyExistingVault(_vault) {
        require(tranche_amount != 0, "ZA");
        _withdraw(msg.sender, _vault, tranche_amount);
    }

    /**
     * @notice Burn the amount of LZYBRA and payback the amount of minted LZYBRA
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `tranche_amount` Must be higher than 0.
     * - `_vault` address of the Centrifuge Vault.
     * @dev Calling the internal`_repay`function.
     */

    function requestWithdraw(
        uint256 tranche_amount,
        address onBehalfOf,
        
    ) external virtual onlyExistingVault(_vault) {
        require(onBehalfOf != address(0), "TZA");
        require(tranche_amount != 0, "ZA");
        require(
            UserAsset[msg.sender] != 0 &&
                UserAsset[msg.sender] >= tranche_amount,
            "ZA"
        );
        uint256 lzybra_amount = calc_share(tranche_amount, _vault);
        
        DOTCv2.requestRedeem(tranche_amount, msg.sender, address(this));
        _repay(msg.sender, _vault, onBehalfOf, lzybra_amount);
        emit RequestWithdrawAsset(
            msg.sender,
            address(collateralAsset),
            _vault,
            tranche_amount,
            block.timestamp
        );
    }

    /**
     * @notice Cancel Deposit Request
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * - `_vault` address of the Centrifuge Vault.
     * @dev Calling the internal`_repay`function.
     */

    function cancelWithdrawRequest(
        
    ) external virtual onlyExistingVault(_vault) {
        require(
            UserDepositedCollatAsset[msg.sender][_vault] != 0,
            "there is no request in process"
        );
        
        DOTCv2.cancelRedeemRequest(0, msg.sender);
        emit CancelDepositRequest(
            msg.sender,
            DOTCv2.asset(),
            _vault,
            block.timestamp
        );
    }

    /**
     * @notice Cancel Deposit Request
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * - `_vault` address of the Centrifuge Vault.
     * @dev Calling the internal`_repay`function.
     */

    function cancelDepositRequest(
        
    ) external virtual onlyExistingVault(_vault) {
        require(
            UserDepReqVaultCollatAsset[msg.sender][_vault] != 0,
            "there is no request in process"
        );
        
        DOTCv2.cancelDepositRequest(0, msg.sender);
        emit CancelDepositRequest(
            msg.sender,
            DOTCv2.asset(),
            _vault,
            block.timestamp
        );
    }

    /**
     * @notice Claim Cancel Deposit Request
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * - `_vault` address of the Centrifuge Vault.
     * @dev Calling the internal`_repay`function.
     */

    function ClaimcancelDepositRequest(
        
    ) external virtual onlyExistingVault(_vault) {
        
        uint256 claimableAsset = DOTCv2.claimableCancelDepositRequest(
            0,
            msg.sender
        );
        require(claimableAsset > 0, "No deposit available to claim");
        uint256 assetAmount = DOTCv2.claimCancelDepositRequest(
            0,
            msg.sender,
            msg.sender
        );
        collateralAsset.safeTransferFrom(
            msg.sender,
            address(this),
            assetAmount
        );
        UserDepReqVaultCollatAsset[_vault][msg.sender] -= assetAmount;
    }

    /**
     * @notice add New Centrifuge Vault
     * Requirements:
     * - `_vault` address of the Centrifuge Vault.
     * @dev only Owner can call this.
     */

    function addVault() external onlyOwner {
        require(!vaultExists[_vault], "Vault already exists");
        vaultExists[_vault] = true;
    }

    /**
     * @notice Remove Centrifuge Vault
     * Requirements:
     * - `_vault` address of the Centrifuge Vault.
     * @dev only Owner can call this.
     */

    function removeVault() external onlyOwner {
        require(vaultExists[_vault], "Vault does not exist");
        delete vaultExists[_vault];
    }

    /**
     * @notice Keeper liquidates borrowers whose collateral ratio is below badCollateralRatio, using LZYBRA provided by Liquidation Provider.
     *
     * Requirements:
     * - onBehalfOf Collateral Ratio should be below badCollateralRatio
     * - assetAmount should be less than 50% of collateral
     * - provider should authorize Zybra to utilize LZYBRA
     * - `_vault` address of the Centrifuge Vault.
     * @dev After liquidation, borrower's debt is reduced by assetAmount * assetPrice, providers and keepers can receive up to an additional 10% liquidation reward.
     */

    function liquidation(
        address provider,
        
        address onBehalfOf,
        uint256 assetAmount
    ) external virtual onlyExistingVault(_vault) {
        uint256 assetPrice = getAssetPrice(withdrawalAsset.assetAddress);
        uint256 onBehalfOfCollateralRatio = (UserDepositedCollatAsset[
            _vault
        ][onBehalfOf] *
            assetPrice *
            100) / getBorrowed(_vault, onBehalfOf);
        require(
            onBehalfOfCollateralRatio <
                configurator.getBadCollateralRatio(address(this)),
            "Borrowers collateral ratio should below badCollateralRatio"
        );

        require(
            assetAmount * 2 <=
                UserDepositedCollatAsset[_vault][onBehalfOf],
            "a max of 50% collateral can be liquidated"
        );
        require(
            LZYBRA.allowance(provider, address(this)) != 0 ||
                msg.sender == provider,
            "provider should authorize to provide liquidation LZYBRA"
        );
        uint256 LZYBRAAmount = (assetAmount * assetPrice) / 1e18;

        _repay(provider, _vault, onBehalfOf, LZYBRAAmount);
        uint256 reducedAsset = assetAmount;
        if (
            onBehalfOfCollateralRatio > 1e20 &&
            onBehalfOfCollateralRatio < 11e19
        ) {
            reducedAsset = (assetAmount * onBehalfOfCollateralRatio) / 1e20;
        }
        if (onBehalfOfCollateralRatio >= 11e19) {
            reducedAsset = (assetAmount * 11) / 10;
        }
        UserDepositedCollatAsset[_vault][onBehalfOf] -= reducedAsset;
        uint256 reward2keeper;
        uint256 keeperRatio = configurator.vaultKeeperRatio(address(this));
        if (
            msg.sender != provider &&
            onBehalfOfCollateralRatio >= 1e20 + keeperRatio * 1e18
        ) {
            reward2keeper = (assetAmount * keeperRatio) / 100;
            collateralAsset.safeTransfer(msg.sender, reward2keeper);
        }
        collateralAsset.safeTransfer(provider, reducedAsset - reward2keeper);
        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            LZYBRAAmount,
            reducedAsset,
            reward2keeper,
            false,
            block.timestamp
        );
    }

    /**
     * @dev Refresh LBR reward before adding providers debt. Refresh Zybra generated service fee before adding totalSupply. Check providers collateralRatio cannot below `safeCollateralRatio`after minting.
     */
    function _mintLZYBRA(
        address _provider,
        uint256 _mintAmount,
        uint256 _assetPrice
    ) internal virtual {
        require(
            poolTotalCirculation + _mintAmount <=
                configurator.mintVaultMaxSupply(address(this)),
            "ESL"
        );
        _updateFee(_provider, _vault);

        borrowed[_vault][_provider] += _mintAmount;
        _checkHealth(_provider, _vault, _assetPrice);

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
        require(
            _amount <= borrowed[_vault][_onBehalfOf],
            "Borrowed Amount is less"
        );
        LZYBRA.transferFrom(msg.sender, address(this), _amount);
        LZYBRA.burn(_amount);
        borrowed[_vault][_onBehalfOf] -= _amount;
        poolTotalCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
    }

    function _withdraw(
        address _provider,
        uint256 offerId,
        uint256 amountToSend
    ) internal virtual {
        
        uint256 maxAmount = DOTCv2.getOffer(offerId).availableAmount;
        require(
            UserAsset[_provider] >= amountToSend,
            "Withdraw amount exceeds deposited amount."
        );
        require(
            maxAmount >= amountToSend && UserAsset[msg.sender] != 0,
            "Withdraw amount exceeds available amount."
        );
         if (getBorrowed(_vault, _provider) > 0) {
            _checkHealth(_provider, _vault, getAssetPrice(withdrawalAsset.assetAddress));
        }
// remaining: checking balance updates
        uint256 _amount = DOTCv2.takeOffer(
            amountToSend,
            offerId,
            _provider
        );
        
        uint256 lzybra_amount = calc_share(amountToSend, _vault);
        
        _repay(msg.sender, _vault, onBehalfOf, lzybra_amount);
        uint256 fee = feeStored[_provider];

        UserAsset[_provider] -= amountToSend;
        UserDepositedCollatAsset[_vault][_provider] -= _amount;

        collateralAsset.safeTransfer(_provider, _amount - fee);

       

        emit WithdrawAsset(
            _provider,
            address(collateralAsset),
            _amount,
            block.timestamp
        );
    }

    /**
     * @dev Get USD value of current collateral asset and minted LZYBRA through price oracle / Collateral asset USD value must higher than safe Collateral Ratio.
     */
    function _checkHealth(
        address user,
        
        uint256 price
    ) internal view {
        if (
            ((UserAsset[user] * price * 100) /
                getBorrowed(_vault, user)) <
            configurator.getSafeCollateralRatio(address(this))
        ) revert("collateralRatio is Below safeCollateralRatio");
    }

    function _updateFee(address user ) internal {
        if (block.timestamp > feeUpdatedAt[user]) {
            feeStored[user] += _newFee(user);
            feeUpdatedAt[user] = block.timestamp;
        }
    }

    function _newFee(
        address user
    ) internal view returns (uint256) {
        return
            (borrowed[_vault][user] *
                configurator.vaultMintFeeApy(address(this)) *
                (block.timestamp - feeUpdatedAt[user])) /
            (86_400 * 365) /
            10_000;
    }

    /**
     * @dev Returns the current borrowing amount for the user, including borrowed[_vault] shares and accumulated fees.
     * @param user The address of the user.
     * @return The total borrowing amount for the user.
     */
    function getBorrowed(
        
        address user
    ) public view returns (uint256) {
        return borrowed[_vault][user] + feeStored[user] + _newFee(user, _vault);
    }

    function getPoolTotalCirculation() external view returns (uint256) {
        return poolTotalCirculation;
    }

    function totalUserDepositedCollatAsset()
        public
        view
        virtual
        returns (uint256)
    {
        return collateralAsset.balanceOf(address(this));
    }

    function isVault() external view returns (bool) {
        return vaultExists[_vault];
    }

    function getAsset() external view returns (address) {
        
        return DOTCv2.asset();
    }

    function getUserTrancheAsset(
        address vault,
        address user
    ) external view returns (uint256) {
        return UserAsset[vault][user];
    }
    function getVaultType() external pure returns (uint8) {
        return 0;
    }

    function calc_share(
        uint256 amount,
        
    ) public view returns (uint256) {
        return (borrowed[_vault][msg.sender] *
            (amount / UserAsset[msg.sender]));
    }

    function getCollateralAssetPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function getAssetPrice(
        
    ) public view returns (uint256) {
        
        (uint128 latestPrice, ) = poolManager.getTranchePrice(
            DOTCv2.poolId(),
            DOTCv2.trancheId(),
            DOTCv2.asset()
        );
        return latestPrice;
    }
}
