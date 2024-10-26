// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interface/ILZYBRA.sol";

contract AdvancedOTCMintBurn is ReentrancyGuard, Ownable {
    IERC20 public usdc;
    ILZYBRA public lzybra;
    AggregatorV3Interface public ethUsdPriceFeed;
    AggregatorV3Interface public usdcUsdPriceFeed;

    uint256 public mintFeePercent = 1; // Fee percentage (1%)
    uint256 public burnFeePercent = 1; // Fee percentage (1%)
    address public feeCollector; // Address to collect fees

    struct Order {
        address user;
        uint256 amount;
        bool isMint; // true if mint order, false if burn order
        uint256 priceLimit;
        uint256 expiry;
        bool executed;
    }

    Order[] public orders;
    mapping(address => uint256[]) public userOrders; // Map to track orders by user

    event MintLzybra(address indexed user, uint256 amount, string asset);
    event BurnLzybra(address indexed user, uint256 amount, string asset);
    event OrderPlaced(address indexed user, uint256 orderId, uint256 amount, bool isMint);
    event OrderExecuted(uint256 indexed orderId, address indexed user, uint256 amount, bool isMint);
    event OrderCancelled(uint256 indexed orderId, address indexed user);
    event BulkOrdersExecuted(uint256[] orderIds, address indexed executor);

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }

    constructor(
        address _usdc,
        address _lzybra,
        address _ethUsdPriceFeed,
        address _usdcUsdPriceFeed,
        address _feeCollector
    ) {
        usdc = IERC20(_usdc);
        lzybra = ILZYBRA(_lzybra);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        usdcUsdPriceFeed = AggregatorV3Interface(_usdcUsdPriceFeed);
        feeCollector = _feeCollector;
    }

    // --- Core OTC Mint/Burn Functions ---
    function mintWithETH() external payable validAmount(msg.value) nonReentrant {
        uint256 ethPriceInUsd = _getLatestPrice(ethUsdPriceFeed);
        uint256 ethAmountInUsd = (msg.value * ethPriceInUsd) / 1e18;
        uint256 mintAmount = _applyFee(ethAmountInUsd, mintFeePercent);

        lzybra.mint(msg.sender, mintAmount);
        emit MintLzybra(msg.sender, mintAmount, "ETH");
    }

    function mintWithUSDC(uint256 amount) external validAmount(amount) nonReentrant {
        usdc.transferFrom(msg.sender, address(this), amount);
        uint256 mintAmount = _applyFee(amount, mintFeePercent);

        lzybra.mint(msg.sender, mintAmount);
        emit MintLzybra(msg.sender, mintAmount, "USDC");
    }

    function burnForETH(uint256 amount) external validAmount(amount) nonReentrant {
        uint256 ethPriceInUsd = _getLatestPrice(ethUsdPriceFeed);
        uint256 ethAmount = ((amount * 1e18) / ethPriceInUsd);
        uint256 burnAmount = _applyFee(amount, burnFeePercent);

        lzybra.burn(msg.sender, burnAmount);
        payable(msg.sender).transfer(ethAmount);
        emit BurnLzybra(msg.sender, burnAmount, "ETH");
    }

    function burnForUSDC(uint256 amount) external validAmount(amount) nonReentrant {
        uint256 burnAmount = _applyFee(amount, burnFeePercent);

        lzybra.burn(msg.sender, burnAmount);
        usdc.transfer(msg.sender, burnAmount);
        emit BurnLzybra(msg.sender, burnAmount, "USDC");
    }

    // --- Order Management ---
    function placeOrder(uint256 amount, bool isMint, uint256 priceLimit, uint256 expiry) external validAmount(amount) {
        require(expiry > block.timestamp, "Order expiry must be in the future");

        uint256 orderId = orders.length;
        orders.push(Order({
            user: msg.sender,
            amount: amount,
            isMint: isMint,
            priceLimit: priceLimit,
            expiry: expiry,
            executed: false
        }));
        
        userOrders[msg.sender].push(orderId);

        emit OrderPlaced(msg.sender, orderId, amount, isMint);
    }

    function executeOrder(uint256 orderId) external nonReentrant {
        require(orderId < orders.length, "Invalid order ID");
        
        Order storage order = orders[orderId];
        require(!order.executed, "Order already executed");
        require(order.expiry > block.timestamp, "Order has expired");

        uint256 price = _getLatestPrice(order.isMint ? ethUsdPriceFeed : usdcUsdPriceFeed);
        bool conditionsMet = (order.isMint && price <= order.priceLimit) ||
                             (!order.isMint && price >= order.priceLimit);
        require(conditionsMet, "Price conditions not met");

        order.executed = true;

        if (order.isMint) {
            mintWithUSDC(order.amount);
        } else {
            burnForUSDC(order.amount);
        }

        emit OrderExecuted(orderId, order.user, order.amount, order.isMint);
    }

    /**
     * @notice Bulk execution of orders by protocol vault or other authorized parties.
     * @param orderIds Array of order IDs to be executed.
     */
    function bulkOrderExecute(uint256[] calldata orderIds) external nonReentrant {
        uint256[] memory executedOrders = new uint256[](orderIds.length);
        uint256 execCount;

        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 orderId = orderIds[i];
            if (orderId < orders.length) {
                Order storage order = orders[orderId];

                if (!order.executed && order.expiry > block.timestamp) {
                    uint256 price = _getLatestPrice(order.isMint ? ethUsdPriceFeed : usdcUsdPriceFeed);
                    bool conditionsMet = (order.isMint && price <= order.priceLimit) ||
                                         (!order.isMint && price >= order.priceLimit);

                    if (conditionsMet) {
                        order.executed = true;
                        if (order.isMint) {
                            mintWithUSDC(order.amount);
                        } else {
                            burnForUSDC(order.amount);
                        }
                        executedOrders[execCount++] = orderId;
                        emit OrderExecuted(orderId, order.user, order.amount, order.isMint);
                    }
                }
            }
        }

        emit BulkOrdersExecuted(executedOrders, msg.sender);
    }

    function cancelOrder(uint256 orderId) external {
        require(orderId < orders.length, "Invalid order ID");
        require(orders[orderId].user == msg.sender, "Not the order owner");
        require(!orders[orderId].executed, "Order already executed");

        orders[orderId].executed = true; // Mark as cancelled
        emit OrderCancelled(orderId, msg.sender);
    }

    // --- Internal Helper Functions ---
    function _applyFee(uint256 amount, uint256 feePercent) internal returns (uint256) {
        uint256 feeAmount = (amount * feePercent) / 100;
        usdc.transfer(feeCollector, feeAmount);
        return amount - feeAmount;
    }

    function _getLatestPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        (, int price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price) * 1e10; // Adjusts price to 18 decimals
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
}
