// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILzybraVault.sol";

contract VaultManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    LzybraVault public vault;
    uint256 public liquidationPenalty; // Liquidation penalty in percentage

    event VaultLiquidated(
        address indexed vaultOwner,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == address(zfiStakingLiquidation), "Not authorized");
        _;
    }

    /**
     * @dev Constructor to initialize the VaultManager contract.
     * @param _vault Reference to the LzybraVault contract.
     * @param _liquidationPenalty Initial penalty applied to seized collateral during liquidation.
     */
    constructor(
        LzybraVault _vault,
        uint256 _liquidationPenalty
    ) {
        require(_liquidationPenalty <= 50, "Penalty too high");
        vault = _vault;
        liquidationPenalty = _liquidationPenalty;
    }

    /**
     * @notice Fetches the collateral and debt for a given vault owner.
     * @param vaultOwner Address of the vault owner.
     * @return collateralAmount Collateral in the vault.
     * @return debtAmount Debt associated with the vault.
     */
    function getVaultCollateral(address vaultOwner)
        external
        view
        returns (uint256 collateralAmount, uint256 debtAmount)
    {
        collateralAmount = vault.UserAsset(vaultOwner, address(vault.collateralAsset()));
        debtAmount = vault.getBorrowed(vaultOwner, address(vault.collateralAsset()));
    }

    /**
     * @notice Liquidates an undercollateralized vault.
     * @param vaultOwner Address of the vault owner to be liquidated.
     * @dev Callable only by authorized parties.
     */
    function liquidateVault(address vaultOwner) external nonReentrant onlyAuthorized {
        (uint256 collateralAmount, uint256 debtAmount) = getVaultCollateral(vaultOwner);
        require(collateralAmount < debtAmount, "Vault not undercollateralized");

        uint256 collateralToSeize = (collateralAmount * (100 + liquidationPenalty)) / 100;

        vault.liquidation(
            msg.sender,
            vaultOwner,
            collateralToSeize,
            Asset({
                assetType: AssetType.ERC20,
                assetAddress: address(vault.collateralAsset()),
                amount: collateralToSeize,
                tokenId: 0,
                assetPrice: AssetPrice(vault.usdc_price_feed(), 0, 0)
            }),
            new bytes(0)
        );

        emit VaultLiquidated(vaultOwner, debtAmount, collateralToSeize);
    }

    // --- Governance and Utility Functions ---

    /**
     * @notice Update the liquidation penalty percentage.
     * @param _liquidationPenalty New liquidation penalty.
     */
    function setLiquidationPenalty(uint256 _liquidationPenalty) external onlyOwner {
        require(_liquidationPenalty <= 50, "Penalty too high");
        liquidationPenalty = _liquidationPenalty;
    }
}
