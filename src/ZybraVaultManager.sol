// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/ILzybraVault.sol"; // Import your LzybraVault

contract VaultManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    LzybraVault public vault;
    uint256 public liquidationPenalty; // Liquidation penalty in percentage
    uint256 public auctionStartPremium; // Percentage premium for starting auction price
    uint256 public auctionStepTime; // Time in seconds between price steps in the auction
    uint256 public auctionCut; // Percentage decrease per step

    struct Auction {
        address vaultOwner;
        uint256 debtAmount;
        uint256 collateralAmount;
        uint256 startTime;
        bool isActive;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionCounter;

    event VaultLiquidated(
        address indexed vaultOwner,
        uint256 auctionId,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event AuctionStarted(uint256 auctionId, uint256 startTime, uint256 startPrice);
    event AuctionPriceReduced(uint256 auctionId, uint256 newPrice);
    event AuctionClosed(uint256 auctionId, address buyer, uint256 finalPrice);

    /**
     * @dev Constructor to initialize the VaultManager contract.
     * @param _vault Reference to the LzybraVault contract.
     * @param _liquidationPenalty Initial penalty applied to seized collateral during liquidation.
     */
    constructor(
        LzybraVault _vault,
        uint256 _liquidationPenalty,
        uint256 _auctionStartPremium,
        uint256 _auctionStepTime,
        uint256 _auctionCut
    ) {
        vault = _vault;
        liquidationPenalty = _liquidationPenalty; // For example, 10 for 10%
        auctionStartPremium = _auctionStartPremium; // Starting premium, e.g., 20 for 20%
        auctionStepTime = _auctionStepTime; // E.g., 60 seconds
        auctionCut = _auctionCut; // E.g., 99 for a 1% decrease
    }

    // --- Vault and Liquidation Functions ---

    /**
     * @notice Fetch vault collateral and debt for a given user.
     * @param vaultOwner Address of the vault owner.
     * @return collateralAmount The collateral held in the user's vault.
     * @return debtAmount The debt associated with the user's vault.
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
     * @notice Liquidate an under-collateralized vault and start an auction.
     * @param vaultOwner Address of the vault owner to be liquidated.
     * @dev Callable only by authorized parties.
     */
    function liquidateVault(address vaultOwner) external nonReentrant {
        (uint256 collateralAmount, uint256 debtAmount) = getVaultCollateral(vaultOwner);
        require(collateralAmount < debtAmount, "Vault is not undercollateralized");

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

        // Start auction at a premium
        uint256 startPrice = (debtAmount * (100 + auctionStartPremium)) / 100;
        auctions[auctionCounter] = Auction({
            vaultOwner: vaultOwner,
            debtAmount: debtAmount,
            collateralAmount: collateralToSeize,
            startTime: block.timestamp,
            isActive: true
        });

        emit VaultLiquidated(vaultOwner, auctionCounter, debtAmount, collateralToSeize);
        emit AuctionStarted(auctionCounter, block.timestamp, startPrice);

        auctionCounter++;
    }

    /**
     * @notice Calculate the current price for an auction based on elapsed time.
     * @param auctionId The ID of the auction.
     * @return The current price for the auction.
     */
    function getCurrentAuctionPrice(uint256 auctionId) public view returns (uint256) {
        Auction memory auction = auctions[auctionId];
        require(auction.isActive, "Auction not active");

        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 steps = elapsed / auctionStepTime;

        uint256 price = (auction.debtAmount * (100 + auctionStartPremium)) / 100;
        return price * (auctionCut**steps) / (100**steps);
    }

    /**
     * @notice Allows a buyer to purchase collateral from an active auction.
     * @param auctionId The ID of the auction.
     * @dev Buyer must send sufficient funds to match the current auction price.
     */
    function buyFromAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.isActive, "Auction is not active");

        uint256 currentPrice = getCurrentAuctionPrice(auctionId);
        require(msg.value >= currentPrice, "Insufficient payment");

        // Complete auction
        auction.isActive = false;

        // Transfer collateral to buyer
        IERC20(vault.collateralAsset()).safeTransfer(msg.sender, auction.collateralAmount);

        // Send funds to the VaultManager owner
        payable(owner()).transfer(currentPrice);

        emit AuctionClosed(auctionId, msg.sender, currentPrice);
    }

    // --- Governance and Utility Functions ---

    /**
     * @notice Update the liquidation penalty.
     * @param _liquidationPenalty New liquidation penalty as a percentage.
     */
    function setLiquidationPenalty(uint256 _liquidationPenalty) public onlyOwner {
        require(_liquidationPenalty <= 50, "Penalty too high");
        liquidationPenalty = _liquidationPenalty;
    }
}
