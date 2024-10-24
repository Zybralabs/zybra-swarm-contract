// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVaultManager {
    function getVaultCollateral(address vaultOwner) external view returns (uint256 collateralAmount, uint256 debtAmount);
    function liquidateVault(address vaultOwner, uint256 auctionId) external;
}

contract ZFIStakingLiquidation is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public zfiToken;  // ZFI token that users will stake
    IVaultManager public vaultManager;  // Vault Manager contract to interact with vaults

    uint256 public totalStaked;
    uint256 public totalProfitDistributed;

    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
    }

    mapping(address => Staker) public stakers;
    uint256 public accProfitPerShare;  // Accumulated profit per share, scaled by 1e12

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event LiquidationProfitDistributed(uint256 amount);
    event LiquidationTriggered(address indexed liquidator, uint256 auctionId, uint256 profit);

    constructor(IERC20 _zfiToken, IVaultManager _vaultManager) {
        zfiToken = _zfiToken;
        vaultManager = _vaultManager;
    }

    // --- Staking and Unstaking Functions ---

    /// @notice Stake ZFI into the pool
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        Staker storage staker = stakers[msg.sender];
        _distributeReward(staker);

        zfiToken.safeTransferFrom(msg.sender, address(this), amount);
        staker.amountStaked += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /// @notice Unstake ZFI from the pool
    function unstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked >= amount, "Insufficient staked amount");

        _distributeReward(staker);

        staker.amountStaked -= amount;
        totalStaked -= amount;
        zfiToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    // --- Liquidation Participation ---

    /// @notice Trigger liquidation of an undercollateralized vault
    function triggerLiquidation(address vaultOwner, uint256 auctionId) external nonReentrant onlyOwner {
        // Step 1: Fetch vault collateral and debt details
        (uint256 collateralAmount, uint256 debtAmount) = vaultManager.getVaultCollateral(vaultOwner);

        // Step 2: Ensure vault is under-collateralized
        require(collateralAmount < debtAmount, "Vault is not undercollateralized");

        // Step 3: Execute liquidation auction through vault manager
        vaultManager.liquidateVault(vaultOwner, auctionId);

        // Step 4: Calculate liquidation profit (simplified: debtAmount - collateralAmount)
        uint256 liquidationProfit = debtAmount - collateralAmount;

        // Step 5: Distribute liquidation profit to stakers
        _distributeLiquidationProfit(liquidationProfit);

        emit LiquidationTriggered(msg.sender, auctionId, liquidationProfit);
    }

    /// @notice Distribute liquidation profit to all stakers
    function _distributeLiquidationProfit(uint256 profitAmount) internal {
        require(totalStaked > 0, "No stakers to distribute profit");
        accProfitPerShare += (profitAmount * 1e12) / totalStaked;
        totalProfitDistributed += profitAmount;

        emit LiquidationProfitDistributed(profitAmount);
    }

    // --- Profit Distribution to Stakers ---

    /// @notice Calculate and distribute the rewards to a staker
    function _distributeReward(Staker storage staker) internal {
        uint256 pendingReward = (staker.amountStaked * accProfitPerShare / 1e12) - staker.rewardDebt;
        if (pendingReward > 0) {
            zfiToken.safeTransfer(msg.sender, pendingReward);
        }
        staker.rewardDebt = staker.amountStaked * accProfitPerShare / 1e12;
    }

    /// @notice View pending reward for a staker
    function pendingReward(address stakerAddress) external view returns (uint256) {
        Staker storage staker = stakers[stakerAddress];
        return (staker.amountStaked * accProfitPerShare / 1e12) - staker.rewardDebt;
    }

    // --- Governance Functions ---

    /// @notice Allows the owner to update the vault manager contract
    function updateVaultManager(IVaultManager _vaultManager) external onlyOwner {
        vaultManager = _vaultManager;
    }

    /// @notice Allows the owner to deposit liquidation profit manually if necessary
    function manualProfitDeposit(uint256 profitAmount) external onlyOwner {
        _distributeLiquidationProfit(profitAmount);
    }
}
