// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LzybraVault.sol"; // Import your LzybraVault

contract VaultManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    LzybraVault public vault; // Reference to the LzybraVault
    uint256 public liquidationPenalty; // Penalty applied to vaults during liquidation, expressed as a percentage (e.g., 10 for 10%)

    event VaultLiquidated(address indexed vaultOwner, uint256 auctionId, uint256 debtRepaid, uint256 collateralSeized);

    /**
     * @dev Constructor to initialize the VaultManager contract with the vault address and liquidation penalty.
     * @param _vault Reference to the LzybraVault contract.
     * @param _liquidationPenalty Percentage penalty applied to seized collateral during liquidation.
     */
    constructor(LzybraVault _vault, uint256 _liquidationPenalty) {
        vault = _vault;
        liquidationPenalty = _liquidationPenalty; // e.g., 10 means 10% penalty on seized collateral
    }

    /**
     * @notice Fetch vault collateral and debt of a user.
     * @param vaultOwner Address of the vault owner whose vault details are being fetched.
     * @return collateralAmount The amount of collateral in the user's vault.
     * @return debtAmount The amount of debt the user has borrowed.
     */
    function getVaultCollateral(address vaultOwner) external view returns (uint256 collateralAmount, uint256 debtAmount) {
        collateralAmount = vault.UserAsset(vaultOwner, address(vault.collateralAsset()));
        debtAmount = vault.getBorrowed(vaultOwner, address(vault.collateralAsset()));
    }

    /**
     * @notice Liquidate an under-collateralized vault.
     * @param vaultOwner Address of the vault owner to be liquidated.
     * @param auctionId Auction ID for tracking the liquidation event.
     * @dev Only callable by the contract owner or authorized keepers, and only if the vault is under-collateralized.
     */
    function liquidateVault(address vaultOwner, uint256 auctionId) external nonReentrant onlyOwner {
        // Step 1: Fetch vault details (collateral and debt)
        (uint256 collateralAmount, uint256 debtAmount) = getVaultCollateral(vaultOwner);

        // Step 2: Ensure the vault is under-collateralized (i.e., collateral-to-debt ratio is below the badCollateralRatio)
        uint256 collateralRatio = (collateralAmount * 100) / debtAmount;
        uint256 badCollateralRatio = vault.configurator().getBadCollateralRatio(address(vault));
        require(collateralRatio < badCollateralRatio, "Vault is not under-collateralized");

        // Step 3: Calculate penalty and liquidation amounts
        // Seize collateral + penalty and repay the debt
        uint256 collateralToSeize = (collateralAmount * (100 + liquidationPenalty)) / 100;
        uint256 debtToRepay = debtAmount;

        // Step 4: Ensure enough collateral exists in the vault
        require(collateralAmount >= collateralToSeize, "Insufficient collateral for liquidation");

        // Step 5: Liquidate the vault
        vault.liquidation(
            msg.sender, // keeper or liquidator
            vaultOwner, // owner of the under-collateralized vault
            collateralToSeize, // amount of collateral being seized
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(vault.collateralAsset()),
                amount: collateralToSeize,
                tokenId: 0,
                assetPrice: AssetPrice(vault.usdc_price_feed(), 0, 0)
            }),
            new bytes(0) // No need for price updates as the external oracle should already handle it
        );

        // Emit liquidation event
        emit VaultLiquidated(vaultOwner, auctionId, debtToRepay, collateralToSeize);
    }

    /**
     * @notice Update the liquidation penalty applied to collateral during liquidation.
     * @param _liquidationPenalty New liquidation penalty percentage (e.g., 10 for 10% penalty).
     * @dev Only callable by the contract owner.
     */
    function setLiquidationPenalty(uint256 _liquidationPenalty) external onlyOwner {
        require(_liquidationPenalty <= 50, "Penalty too high"); // Adding a sanity check for the maximum penalty
        liquidationPenalty = _liquidationPenalty;
    }
}
