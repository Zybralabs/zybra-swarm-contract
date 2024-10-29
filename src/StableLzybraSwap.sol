// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/ILZYBRA.sol";

contract StableLzybraSwap is ReentrancyGuard, Ownable {
    IERC20 public usdc;
    ILZYBRA public lzybra;
    AggregatorV3Interface public ethUsdPriceFeed;
    
    uint256 public mintFeePercent = 1; // Fee percentage (1%)
    uint256 public burnFeePercent = 1; // Fee percentage (1%)
    uint256 public minMintAmount = 10 * 1e18; // Minimum amount for minting, example: $10
    uint256 public maxMintAmount = 10000 * 1e18; // Maximum amount for minting, example: $10,000
    
    address public feeCollector;

    event MintedWithUSDC(address indexed user, uint256 amount);
    event MintedWithETH(address indexed user, uint256 amount);
    event BurnedForUSDC(address indexed user, uint256 amount);
    event BurnedForETH(address indexed user, uint256 amount);
    event FeeCollected(uint256 feeAmount, address feeCollector);

    modifier validAmount(uint256 amount) {
        require(amount >= minMintAmount, "Amount below minimum mint limit");
        require(amount <= maxMintAmount, "Amount exceeds maximum mint limit");
        _;
    }

    constructor(
        address _usdc,
        address _lzybra,
        address _ethUsdPriceFeed,
        address _feeCollector
    ) {
        usdc = IERC20(_usdc);
        lzybra = ILZYBRA(_lzybra);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        feeCollector = _feeCollector;
    }

    // --- Minting Functions ---

    /**
     * @dev Mints Lzybra with USDC at a 1:1 rate minus fees, within allowed limits.
     */
    function mintWithUSDC(uint256 usdcAmount) external validAmount(usdcAmount) nonReentrant {
        usdc.transferFrom(msg.sender, address(this), usdcAmount);
        uint256 mintAmount = _applyFee(usdcAmount, mintFeePercent);
        lzybra.mint(msg.sender, mintAmount);
        emit MintedWithUSDC(msg.sender, mintAmount);
    }

    /**
     * @dev Mints Lzybra using ETH, converting ETH to USD at the current price, within allowed limits.
     */
    function mintWithETH() external payable nonReentrant {
        uint256 ethPriceInUsd = _getLatestPrice(ethUsdPriceFeed);
        uint256 ethAmountInUsd = (msg.value * ethPriceInUsd) / 1e18;
        require(ethAmountInUsd >= minMintAmount && ethAmountInUsd <= maxMintAmount, "Mint amount out of limits");
        
        uint256 mintAmount = _applyFee(ethAmountInUsd, mintFeePercent);
        lzybra.mint(msg.sender, mintAmount);
        emit MintedWithETH(msg.sender, mintAmount);
    }

    // --- Burning Functions ---

    /**
     * @dev Burns Lzybra to receive USDC at a 1:1 rate minus fees, within allowed limits.
     */
    function burnForUSDC(uint256 lzybraAmount) external validAmount(lzybraAmount) nonReentrant {
        uint256 burnAmount = _applyFee(lzybraAmount, burnFeePercent);
        lzybra.burn(msg.sender, burnAmount);
        usdc.transfer(msg.sender, burnAmount);
        emit BurnedForUSDC(msg.sender, burnAmount);
    }

    /**
     * @dev Burns Lzybra to receive ETH, converting USD to ETH at the current price, within allowed limits.
     */
    function burnForETH(uint256 lzybraAmount) external validAmount(lzybraAmount) nonReentrant {
        uint256 ethPriceInUsd = _getLatestPrice(ethUsdPriceFeed);
        uint256 ethAmount = (lzybraAmount * 1e18) / ethPriceInUsd;
        uint256 burnAmount = _applyFee(lzybraAmount, burnFeePercent);

        lzybra.burn(msg.sender, burnAmount);
        (bool sent, ) = payable(msg.sender).call{value: ethAmount}("");
        require(sent, "ETH transfer failed");
        emit BurnedForETH(msg.sender, burnAmount);
    }

    // --- Internal Helper Functions ---

    /**
     * @dev Applies fee and transfers fee amount to fee collector.
     */
    function _applyFee(uint256 amount, uint256 feePercent) internal returns (uint256) {
        uint256 feeAmount = (amount * feePercent + 99) / 100; // Round up for precision
        require(usdc.balanceOf(address(this)) >= feeAmount, "Insufficient balance for fee");
        usdc.transfer(feeCollector, feeAmount);
        emit FeeCollected(feeAmount, feeCollector);
        return amount - feeAmount;
    }

    /**
     * @dev Gets the latest price from the Chainlink price feed.
     */
    function _getLatestPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        (, int price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price) * 1e10; // Adjust to 18 decimals
    }

    // --- Governance Functions ---

    function updateMintFee(uint256 _mintFeePercent) external onlyOwner {
        mintFeePercent = _mintFeePercent;
    }

    function updateBurnFee(uint256 _burnFeePercent) external onlyOwner {
        burnFeePercent = _burnFeePercent;
    }

    function updateFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function updateMintLimits(uint256 _minMintAmount, uint256 _maxMintAmount) external onlyOwner {
        require(_minMintAmount > 0, "Minimum mint amount must be positive");
        require(_maxMintAmount > _minMintAmount, "Maximum must be greater than minimum");
        minMintAmount = _minMintAmount;
        maxMintAmount = _maxMintAmount;
    }

    receive() external payable {}

    function withdrawExcessETH() external onlyOwner {
        uint256 excessBalance = address(this).balance;
        (bool sent, ) = payable(feeCollector).call{value: excessBalance}("");
        require(sent, "Withdraw failed");
    }
}
