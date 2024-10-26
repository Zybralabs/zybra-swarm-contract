// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IVaultManager {
    function getVaultCollateral(address vaultOwner) external view returns (uint256 collateralAmount, uint256 debtAmount);
    function liquidateVault(address vaultOwner, uint256 auctionId) external;
}

interface IOTCWithMintBurn {
    function convertETHToLzybra(uint256 ethAmount) external payable;
}

contract ZFIStakingLiquidation is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public zfiToken;
    IVaultManager public vaultManager;
    IOTCWithMintBurn public otcContract;
    ISwapRouter public immutable uniswapRouter;

    address public immutable WETH;
    uint256 public totalStaked;
    uint256 public totalProfitDistributed;
    uint256 public keeperRewardPercent = 2;  // Percent of liquidation profit to keepers

    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
    }

    mapping(address => Staker) public stakers;
    uint256 public accProfitPerShare;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event ProfitDistributed(uint256 amount);
    event LiquidationTriggered(address indexed liquidator, uint256 auctionId, uint256 profit, uint256 keeperReward);
    event RewardWithdrawn(address indexed user, uint256 reward);

    constructor(
        IERC20 _zfiToken,
        IVaultManager _vaultManager,
        IOTCWithMintBurn _otcContract,
        ISwapRouter _uniswapRouter,
        address _WETH
    ) {
        zfiToken = _zfiToken;
        vaultManager = _vaultManager;
        otcContract = _otcContract;
        uniswapRouter = _uniswapRouter;
        WETH = _WETH;
    }

    // --- New Uniswap and OTC Conversion Functions ---

    /**
     * @dev Converts ZFI to Lzybra via Uniswap (ZFI to WETH) and OTC (WETH to Lzybra).
     * @param zfiAmount The amount of ZFI to convert.
     */
    function _convertZFIToLzybra(uint256 zfiAmount) internal {
        require(zfiToken.balanceOf(address(this)) >= zfiAmount, "Insufficient ZFI");

        // Approve Uniswap Router to spend ZFI
        zfiToken.safeApprove(address(uniswapRouter), zfiAmount);

        // Define Uniswap V3 swap parameters for ZFI to WETH
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(zfiToken),
            tokenOut: WETH,
            fee: 3000,  // Pool fee tier of 0.3%
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: zfiAmount,
            amountOutMinimum: 0,  // Set to zero or estimate based on slippage tolerance
            sqrtPriceLimitX96: 0
        });

        // Execute the swap from ZFI to WETH on Uniswap
        uint256 wethAmount = uniswapRouter.exactInputSingle(params);

        // Convert WETH to ETH and send to OTC contract to mint Lzybra
        IWETH(WETH).withdraw(wethAmount);
        otcContract.convertETHToLzybra{value: wethAmount}();
    }

    // --- Staking and Unstaking Functions ---

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        Staker storage staker = stakers[msg.sender];
        _distributeReward(staker);

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

    function triggerLiquidation(address vaultOwner, uint256 auctionId) external nonReentrant {
        (uint256 collateralAmount, uint256 debtAmount) = vaultManager.getVaultCollateral(vaultOwner);
        require(collateralAmount < debtAmount, "Vault is not undercollateralized");

        uint256 amountToConvert = debtAmount - collateralAmount;
        _convertZFIToLzybra(amountToConvert);

        // Use converted Lzybra for liquidation
        vaultManager.liquidateVault(vaultOwner, auctionId);

        uint256 liquidationProfit = debtAmount - collateralAmount;
        uint256 keeperReward = (liquidationProfit * keeperRewardPercent) / 100;

        zfiToken.safeTransfer(msg.sender, keeperReward);  // Transfer keeper reward
        _distributeLiquidationProfit(liquidationProfit - keeperReward);  // Distribute profit to stakers

        emit LiquidationTriggered(msg.sender, auctionId, liquidationProfit, keeperReward);
    }

    function batchTriggerLiquidations(address[] calldata vaultOwners, uint256[] calldata auctionIds) external nonReentrant {
        require(vaultOwners.length == auctionIds.length, "Mismatched input lengths");

        for (uint256 i = 0; i < vaultOwners.length; i++) {
            (uint256 collateralAmount, uint256 debtAmount) = vaultManager.getVaultCollateral(vaultOwners[i]);
            if (collateralAmount < debtAmount) {
                uint256 amountToConvert = debtAmount - collateralAmount;
                _convertZFIToLzybra(amountToConvert);

                vaultManager.liquidateVault(vaultOwners[i], auctionIds[i]);

                uint256 liquidationProfit = debtAmount - collateralAmount;
                uint256 keeperReward = (liquidationProfit * keeperRewardPercent) / 100;

                zfiToken.safeTransfer(msg.sender, keeperReward);
                _distributeLiquidationProfit(liquidationProfit - keeperReward);

                emit LiquidationTriggered(msg.sender, auctionIds[i], liquidationProfit, keeperReward);
            }
        }
    }

    function _distributeLiquidationProfit(uint256 profitAmount) internal {
        require(totalStaked > 0, "No stakers to distribute profit");
        accProfitPerShare += (profitAmount * 1e12) / totalStaked;
        totalProfitDistributed += profitAmount;

        emit ProfitDistributed(profitAmount);
    }

    // --- Profit Withdrawal Functions ---

    function withdrawReward() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        uint256 pendingReward = _calculatePendingReward(staker);

        require(pendingReward > 0, "No reward to withdraw");

        staker.rewardDebt = staker.amountStaked * accProfitPerShare / 1e12;
        zfiToken.safeTransfer(msg.sender, pendingReward);

        emit RewardWithdrawn(msg.sender, pendingReward);
    }

    function _distributeReward(Staker storage staker) internal {
        uint256 pendingReward = _calculatePendingReward(staker);
        if (pendingReward > 0) {
            zfiToken.safeTransfer(msg.sender, pendingReward);
        }
        staker.rewardDebt = staker.amountStaked * accProfitPerShare / 1e12;
    }

    function _calculatePendingReward(Staker storage staker) internal view returns (uint256) {
        return (staker.amountStaked * accProfitPerShare / 1e12) - staker.rewardDebt;
    }

    function pendingReward(address stakerAddress) external view returns (uint256) {
        Staker storage staker = stakers[stakerAddress];
        return _calculatePendingReward(staker);
    }

    // --- Governance Functions ---

    function updateVaultManager(IVaultManager _vaultManager) external onlyOwner {
        vaultManager = _vaultManager;
    }

    function updateOTCContract(IOTCWithMintBurn _otcContract) external onlyOwner {
        otcContract = _otcContract;
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
