// SPDX-License-Identifier: BUSL-1.1

/**
 * @title Zybra Protocol V2 Configurator Contract
 * @dev The Configurator contract is used to set various parameters and control functionalities of the Zybra Protocol. It is based on OpenZeppelin's Proxy and AccessControl libraries, allowing the DAO to control contract upgrades. There are three types of governance roles:
 * * DAO: A time-locked contract initiated by esLBR voting, with a minimum effective period of 14 days. After the vote is passed, only the developer can execute the action.
 * * TIMELOCK: A time-locked contract controlled by the developer, with a minimum effective period of 2 days.
 * * ADMIN: A multisignature account controlled by the developer.
 * All setting functions have three levels of calling permissions:
 * * onlyOwner: Only callable by the DAO for governance purposes.
 * * onlyOwner: Callable by both the DAO and the TIMELOCK contract.
 * *: Callable by all governance roles.
 */

pragma solidity ^0.8.17;

import "../interfaces/Ilzybra.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

interface IProtocolRewardsPool {
    function notifyRewardAmount(uint256 amount, uint256 tokenType) external;
}

interface IlzybraMiningIncentives {
    function refreshReward(address user) external;
}

interface IVault {
    function getVaultType() external view returns (uint8);
}


contract ZybraConfigurator is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    mapping(address => bool) public mintVault;
    mapping(address => uint256) public mintVaultMaxSupply;
    mapping(address => bool) public vaultMintPaused;
    mapping(address => bool) public vaultBurnPaused;
    mapping(address => uint256) vaultSafeCollateralRatio;
    mapping(address => uint256) vaultBadCollateralRatio;
    mapping(address => uint256) public vaultMintFeeApy;
    mapping(address => uint256) public vaultKeeperRatio;
    mapping(address => bool) redemptionProvider;
    mapping(address => bool) public tokenMiner;
    mapping(address => uint256) vaultWeight;


    uint256 public redemptionFee;

    IlzybraMiningIncentives public lzybraMiningIncentives;
    IProtocolRewardsPool public ZybraProtocolRewardsPool;
    ILZYBRA public lzybra;
    uint256 public flashloanFee;
    // Limiting the maximum percentage of lzybra that can be cross-chain transferred to L2 in relation to the total supply.
    uint256 maxStableRatio;
    address public stableToken;
    bool public premiumTradingEnabled;


    event RedemptionFeeChanged(uint256 newSlippage);
    event SafeCollateralRatioChanged(address indexed pool, uint256 newRatio);
    event BadCollateralRatioChanged(address indexed pool, uint256 newRatio);
    event RedemptionProvider(address indexed user, bool status);
    event ProtocolRewardsPoolChanged(address indexed pool, uint256 timestamp);
    event BorrowApyChanged(address indexed pool, uint256 newApy);
    event KeeperRatioChanged(address indexed pool, uint256 newSlippage);
    event TokenMinerChanges(address indexed pool, bool status);
    event VaultWeightChanged(address indexed pool, uint256 weight, uint256 timestamp);
    event SendProtocolRewards(address indexed token, uint256 amount, uint256 timestamp);
    event CurvePoolChanged(address oldAddr, address newAddr, uint256 timestamp);

    /// @notice Emitted when the fees for flash loaning a token have been updated
    /// @param fee The new fee for this token as a percentage and multiplied by 100 to avoid decimals (for example, 10% is 10_00)
    event FlashloanFeeUpdated(uint256 fee);



function initialize(address _lzybra, address _stableToken) public initializer {
        __Ownable_init();
        redemptionFee = 50;
        flashloanFee = 500;
        maxStableRatio = 5_000;
        stableToken = _stableToken;
        lzybra = ILZYBRA(_lzybra);
    }

 function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /**
     * @notice Controls the minting limit of lzybra for an asset pool.
     * @param pool The address of the asset pool.
     * @param maxSupply The maximum amount of lzybra that can be minted for the asset pool.
     * @dev This function can only be called by the DAO.
     */
    function setMintVaultMaxSupply(address pool, uint256 maxSupply) external onlyOwner {
        mintVaultMaxSupply[pool] = maxSupply;
    }

    /**
     * @notice  badCollateralRatio can be decided by DAO,starts at 130%
     */
    function setBadCollateralRatio(address pool, uint256 newRatio) external onlyOwner {
        require(newRatio >= 50 * 1e18 && newRatio <= 90 * 1e18 && newRatio <= vaultSafeCollateralRatio[pool] - 1e19, "LNA");
        vaultBadCollateralRatio[pool] = newRatio;
        emit BadCollateralRatioChanged(pool, newRatio);
    }

    /**
     * @notice Sets the address of the protocol rewards pool.
     * @param addr The new address of the protocol rewards pool.
     * @dev This function can only be called by accounts with TIMELOCK or higher privilege.
     */
    function setProtocolRewardsPool(address addr) external onlyOwner {
        ZybraProtocolRewardsPool = IProtocolRewardsPool(addr);
        emit ProtocolRewardsPoolChanged(addr, block.timestamp);
    }


    function setVaultWeight(address vault, uint256 weight) external onlyOwner {
        require(mintVault[vault], "NV");
        require(weight <= 2e20, "EL");
        vaultWeight[vault] = weight;
        emit VaultWeightChanged(vault, weight, block.timestamp);
    }


   

    /**
     * @notice Sets the status of premium trading.
     * @param isActive Boolean value indicating whether premium trading is enabled or disabled.
     * @dev This function can only be called by accounts with TIMELOCK or higher privilege.
     */
    function setPremiumTradingEnabled(bool isActive) external onlyOwner {
        premiumTradingEnabled = isActive;
    }

    /**
     * @notice Enables or disables the repayment functionality for a asset pool.
     * @param pool The address of the pool.
     * @param isActive Boolean value indicating whether repayment is active or paused.
     * @dev This function can only be called by accounts with TIMELOCK or higher privilege.
     */
    function setVaultBurnPaused(address pool, bool isActive) external onlyOwner {
        vaultBurnPaused[pool] = isActive;
    }

    /**
     * @notice Enables or disables the mint functionality for a asset pool.
     * @param pool The address of the pool.
     * @param isActive Boolean value indicating whether minting is active or paused.
     * @dev This function can only be called by accounts with ADMIN or DAO.
     */
    function setVaultMintPaused(address pool, bool isActive) external {
        vaultMintPaused[pool] = isActive;
    }

    /**
     * @notice Sets the redemption fee.
     * @param newFee The new fee to be set.
     * @notice The fee cannot exceed 5%.
     */
    function setRedemptionFee(uint256 newFee) external onlyOwner {
        require(newFee <= 500, "Max Redemption Fee is 5%");
        redemptionFee = newFee;
        emit RedemptionFeeChanged(newFee);
    }

    /**
     * @notice  safeCollateralRatio can be decided by TIMELOCK.
     * The lzybra vault requires a minimum safe collateral rate of 160%,
     * On the other hand, the lzybra vault requires a safe collateral rate at least 10% higher
     * than the liquidation collateral rate, providing an additional buffer to protect against liquidation risks.
     */
    function setSafeCollateralRatio(address pool, uint256 newRatio) external onlyOwner {
        if(IVault(pool).getVaultType() == 0) {
            require(newRatio >= 160 * 1e18, "lzybra vault safe collateralRatio should more than 160%");
        } else {
            require(newRatio >= vaultBadCollateralRatio[pool] + 1e19, "lzybra vault safe collateralRatio should more than bad collateralRatio");
        }
        vaultSafeCollateralRatio[pool] = newRatio;
        emit SafeCollateralRatioChanged(pool, newRatio);
    }

    /**
     * @notice  Set the borrowing annual percentage yield (APY) for a asset pool.
     * @param pool The address of the pool to set the borrowing APY for.
     * @param newApy The new borrowing APY to set, limited to a maximum of 2%.
     */
    function setBorrowApy(address pool, uint256 newApy) external onlyOwner {
        require(newApy <= 200, "Borrow APY cannot exceed 2%");
        vaultMintFeeApy[pool] = newApy;
        emit BorrowApyChanged(pool, newApy);
    }

    /**
     * @notice Set the reward ratio for the liquidator after liquidation.
     * @param pool The address of the pool to set the reward ratio for.
     * @param newRatio The new reward ratio to set, limited to a maximum of 5%.
     */
    function setKeeperRatio(address pool,uint256 newRatio) external onlyOwner {
        require(newRatio <= 5, "Max Keeper reward is 5%");
        vaultKeeperRatio[pool] = newRatio;
        emit KeeperRatioChanged(pool, newRatio);
    }

    /**
     * @notice Sets the mining permission for the esLBR&LBR mining pool.
     * @param _contracts An array of addresses representing the contracts.
     * @param _bools An array of booleans indicating whether mining is allowed for each contract.
     */
    function setTokenMiner(address[] calldata _contracts, bool[] calldata _bools) external onlyOwner {
        for (uint256 i = 0; i < _contracts.length; i++) {
            tokenMiner[_contracts[i]] = _bools[i];
            emit TokenMinerChanges(_contracts[i], _bools[i]);
        }
    }

    /**
     * dev Sets the maximum percentage share for lzybra.
     * @param _ratio The ratio in basis points (1/10_000). The maximum value is 10_000.
     */
    function setMaxStableRatio(uint256 _ratio) external onlyOwner {
        require(_ratio <= 10_000, "The maximum value is 10_000");
        maxStableRatio = _ratio;
    }

    /// @notice Update the flashloan fee percentage, only available to the manager of the contract
    /// @param fee The fee percentage for lzybra, multiplied by 100 (for example, 10% is 1000)
    function setFlashloanFee(uint256 fee) external onlyOwner {
        if (fee > 10_000) revert('EL');
        emit FlashloanFeeUpdated(fee);
        flashloanFee = fee;
    }

    /**
     * @notice User chooses to become a Redemption Provider
     */
    function becomeRedemptionProvider(bool _bool) external {
        lzybraMiningIncentives.refreshReward(msg.sender);
        redemptionProvider[msg.sender] = _bool;
        emit RedemptionProvider(msg.sender, _bool);
    }

    /**
     * @dev Updates the mining data for the user's lzybra mining incentives.
     */
    function refreshMintReward(address user) external {
        lzybraMiningIncentives.refreshReward(user);
    }
    
    /**
     * @dev Returns the address of the Zybra protocol rewards pool.
     * @return The address of the Zybra protocol rewards pool.
     */
    function getProtocolRewardsPool() external view returns (address) {
        return address(ZybraProtocolRewardsPool);
    }

    /**
     * @notice Distributes rewards to the ZybraProtocolRewardsPool based on the available balance of lzybra and eUSD. 
     * If the balance is greater than 1e21, the distribution process is triggered.
     * 
     * First, if the eUSD balance is greater than 1,000 and the premiumTradingEnabled flag is set to true, 
     * and the eUSD/USDC premium exceeds 0.5%, eUSD will be exchanged for USDC and added to the ZybraProtocolRewardsPool. 
     * Otherwise, eUSD will be directly converted to lzybra, and the entire lzybra balance will be transferred to the ZybraProtocolRewardsPool.
     * @dev The protocol rewards amount is notified to the ZybraProtocolRewardsPool for proper reward allocation.
     */
    function distributeRewards() external {
        uint256 USDBalance = IERC20(stableToken).balanceOf(address(this));
        if(USDBalance >= 1e21) {
            IERC20(stableToken).transfer(address(ZybraProtocolRewardsPool), USDBalance);
            ZybraProtocolRewardsPool.notifyRewardAmount(USDBalance, 0);
            emit SendProtocolRewards(address(stableToken), USDBalance, block.timestamp);
        }
    }

    /**
     * @dev Returns the safe collateral ratio for a asset pool.
     * @param pool The address of the pool to check.
     * @return The safe collateral ratio for the specified pool.
     */
    function getSafeCollateralRatio(
        address pool
    ) public view returns (uint256) {
        if (vaultSafeCollateralRatio[pool] == 0) return 160 * 1e18;
        return vaultSafeCollateralRatio[pool];
    }

    function getBadCollateralRatio(address pool) external view returns(uint256) {
        if(vaultBadCollateralRatio[pool] == 0) return getSafeCollateralRatio(pool) - 1e19;
        return vaultBadCollateralRatio[pool];
    }

    function getVaultWeight(
        address pool
    ) external view returns (uint256) {
        if(!mintVault[pool]) return 0;
        if (vaultWeight[pool] == 0) return 100 * 1e18;
        return vaultWeight[pool];
    }

    /**
     * @dev Checks if a user is a redemption provider.
     * @param user The address of the user to check.
     * @return True if the user is a redemption provider, false otherwise.
     */
    function isRedemptionProvider(address user) external view returns (bool) {
        return redemptionProvider[user];
    }


}
