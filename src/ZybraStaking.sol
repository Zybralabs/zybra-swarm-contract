// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../node_modules/@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./StableLzybraSwap.sol";
import "./interfaces/IWETH.sol";

interface IVaultManager {
    function getVaultCollateral(address vaultOwner, address collateralAsset) external view returns (uint256 collateralAmount, uint256 debtAmount);
    function liquidateVault(address vaultOwner, address collateralAsset, uint256 assetAmount, bytes[] calldata priceUpdate) external payable;
}

contract ZFIStakingLiquidation is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public zfiToken;
    IVaultManager public vaultManager;
    StableLzybraSwap public stableLzybraSwap;
    ISwapRouter public uniswapRouter;
    address public WETH;
    
    uint256 public totalStaked;
    uint256 public totalProfitDistributed;
    uint256 public keeperRewardPercent;

    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
    }

    mapping(address => Staker) public stakers;
    uint256 public accProfitPerShare;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event ProfitDistributed(uint256 amount);
    event LiquidationTriggered(address indexed liquidator, address indexed vaultOwner, uint256 profit, uint256 keeperReward);
    event RewardWithdrawn(address indexed user, uint256 reward);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the required parameters.
     */
    function initialize(
        IERC20Upgradeable _zfiToken,
        address _vaultManager,
        StableLzybraSwap _stableLzybraSwap,
        ISwapRouter _uniswapRouter,
        address _WETH
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        zfiToken = _zfiToken;
        vaultManager = IVaultManager(_vaultManager);
        stableLzybraSwap = _stableLzybraSwap;
        uniswapRouter = _uniswapRouter;
        WETH = _WETH;
        keeperRewardPercent = 2;
    }

    // --- UUPS Upgradeability Requirement ---
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // --- Uniswap and StableLzybraSwap Conversion Functions ---

    function _convertZFIToLzybra(uint256 zfiAmount) internal {
        require(zfiToken.balanceOf(address(this)) >= zfiAmount, "Insufficient ZFI");

        zfiToken.safeApprove(address(uniswapRouter), zfiAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(zfiToken),
            tokenOut: WETH,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: zfiAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 wethAmount = uniswapRouter.exactInputSingle(params);
        IWETH(WETH).withdraw(wethAmount);
        stableLzybraSwap.mintWithETH{value: wethAmount}();
    }

    function _convertRwaToUSDC(address rwaToken, uint256 rwaAmount) internal returns (uint256) {
        require(IERC20Upgradeable(rwaToken).balanceOf(address(this)) >= rwaAmount, "Insufficient RWA for conversion");
        IERC20Upgradeable(rwaToken).safeApprove(address(stableLzybraSwap), rwaAmount);
        // uint256 usdcAmount = stableLzybraSwap.convertRwaToUSDC(rwaAmount);
        uint256 usdcAmount = 100*10**18;
        require(usdcAmount > 0, "RWA to USDC conversion failed");

        return usdcAmount;
    }

    function _convertUSDCToZFIWithUniswap(uint256 usdcAmount) internal returns (uint256) {
        // IERC20Upgradeable usdcToken = stableLzybraSwap.usdcToken();
        IERC20Upgradeable usdcToken = IERC20Upgradeable(0x8f87BFdd966FfaF1DF9B305AcE736C5Cc9BecfD6);
        require(usdcToken.balanceOf(address(this)) >= usdcAmount, "Insufficient USDC for conversion");
        usdcToken.safeApprove(address(uniswapRouter), usdcAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(usdcToken),
            tokenOut: address(zfiToken),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: usdcAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 zfiAmount = uniswapRouter.exactInputSingle(params);
        require(zfiAmount > 0, "USDC to ZFI swap failed");

        return zfiAmount;
    }

    // --- Staking and Unstaking Functions ---

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        Staker storage staker = stakers[msg.sender];

        zfiToken.safeTransferFrom(msg.sender, address(this), amount);
        staker.amountStaked += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked >= amount, "Insufficient staked amount");

        _distributeReward(staker);

        staker.amountStaked -= amount;
        totalStaked -= amount;
        zfiToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    // --- Liquidation and Profit Distribution Functions ---

    function triggerLiquidation(
        address vaultOwner,
        address collateralAsset,
        uint256 assetAmount,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant {
        (uint256 collateralAmount, uint256 debtAmount) = vaultManager.getVaultCollateral(vaultOwner, collateralAsset);
        require(collateralAmount < debtAmount, "Vault is not undercollateralized");

        uint256 amountToConvert = debtAmount - collateralAmount;
        _convertZFIToLzybra(amountToConvert);

        vaultManager.liquidateVault{value: msg.value}(vaultOwner, collateralAsset, assetAmount, priceUpdate);

        uint256 rwaReceived = getRwaAmountFromLiquidation();
        // uint256 usdcAmount = _convertRwaToUSDC(address(WETH),rwaReceived ); //fix here
        uint256 usdcAmount = _convertRwaToUSDC(address(WETH),rwaReceived );
        uint256 profitAmount = _convertUSDCToZFIWithUniswap(usdcAmount);

        uint256 keeperReward = (profitAmount * keeperRewardPercent) / 100;
        uint256 stakerProfit = profitAmount - keeperReward;

        if (keeperReward > 0) {
            zfiToken.safeTransfer(msg.sender, keeperReward);
        }

        _distributeLiquidationProfit(stakerProfit);
        emit LiquidationTriggered(msg.sender, vaultOwner, profitAmount, keeperReward);
    }

    function _distributeLiquidationProfit(uint256 profitAmount) internal {
        require(totalStaked > 0, "No stakers to distribute profit");
        accProfitPerShare += (profitAmount * 1e12) / totalStaked;
        totalProfitDistributed += profitAmount;

        emit ProfitDistributed(profitAmount);
    }

    function getRwaAmountFromLiquidation() internal view returns (uint256) {
        return 1000; // Mock value for testing purposes
    }

    // --- Profit Withdrawal Functions ---

    function withdrawReward() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        uint256 pendingReward = _calculatePendingReward(staker);

        require(pendingReward > 0, "No reward to withdraw");

        staker.rewardDebt = (staker.amountStaked * accProfitPerShare) / 1e12;
        zfiToken.safeTransfer(msg.sender, pendingReward);

        emit RewardWithdrawn(msg.sender, pendingReward);
    }

    function _distributeReward(Staker storage staker) internal {
        uint256 pendingReward = _calculatePendingReward(staker);
        if (pendingReward > 0) {
            zfiToken.safeTransfer(msg.sender, pendingReward);
        }
        staker.rewardDebt = (staker.amountStaked * accProfitPerShare) / 1e12;
    }

    function _calculatePendingReward(Staker storage staker) internal view returns (uint256) {
        return (staker.amountStaked * accProfitPerShare) / 1e12 - staker.rewardDebt;
    }

    // --- Governance Functions ---

    function updateVaultManager(IVaultManager _vaultManager) external onlyOwner {
        vaultManager = _vaultManager;
    }

    function updateStableLzybraSwap(StableLzybraSwap _stableLzybraSwap) external onlyOwner {
        stableLzybraSwap = _stableLzybraSwap;
    }

    function setKeeperRewardPercent(uint256 _keeperRewardPercent) external onlyOwner {
        require(_keeperRewardPercent <= 10, "Max 10%");
        keeperRewardPercent = _keeperRewardPercent;
    }

    function manualProfitDeposit(uint256 profitAmount) external onlyOwner {
        _distributeLiquidationProfit(profitAmount);
    }

    receive() external payable {}
}
