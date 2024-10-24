// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ILZYBRA} from "./interface/ILZYBRA.sol";  // Assuming Lzybra is the token contract you provided

/**
 * @title OTCWithMintBurn
 * @notice OTC contract for exchanging USDC to ETH with minting and burning Lzybra tokens
 */
contract OTCWithMintBurn is ReentrancyGuard {
    IERC20 public usdc;    // USDC token interface
    ILZYBRA public lzybra;  // Lzybra token interface

    struct Party {
        address addr;
        bool deposited;
        bool signed;
        bool rescinded;
    }

    struct Periods {
        uint256 depositTime;
        uint256 signingTime;
    }

    Periods public periods;
    Party public partyA;  // ETH -> Lzybra
    Party public partyB;  // USDC -> ETH

    event Deposit(address indexed party, uint256 amount);
    event Withdraw(address indexed party, uint256 amount);
    event Sign(address indexed party);
    event Rescind(address indexed party, uint256 amount);

    constructor(
        IERC20 _usdc,       // USDC token address
        Lzybra _lzybra,     // Lzybra token address
        address _partyA,
        address _partyB,
        uint256 _depositTime,
        uint256 _signingTime
    ) {
        usdc = _usdc;
        lzybra = _lzybra;
        _initContract(
            _partyA,
            _partyB,
            block.timestamp + _depositTime,
            block.timestamp + _depositTime + _signingTime
        );
    }

    modifier depositReview(address party) {
        require(
            parties[msg.sender].addr == party &&
            !parties[msg.sender].deposited &&
            !parties[msg.sender].signed &&
            !parties[msg.sender].rescinded,
            "OTC: Deposit conditions not met"
        );
        if (block.timestamp > periods.depositTime) {
            _returnDeposits();
        }
        _;
    }

    modifier signingReview() {
        require(
            (msg.sender == partyA.addr || msg.sender == partyB.addr) &&
            parties[msg.sender].deposited &&
            !parties[msg.sender].signed &&
            !parties[msg.sender].rescinded,
            "OTC: Signing conditions not met"
        );
        if (block.timestamp > periods.signingTime) {
            _returnDeposits();
        }
        _;
    }

    modifier exchangeReview(address party) {
        require(
            parties[msg.sender].addr == party &&
            parties[msg.sender].deposited &&
            parties[msg.sender].signed &&
            !parties[msg.sender].rescinded,
            "OTC: Withdraw conditions not met"
        );
        _;
    }

    /// @notice USDC depositor (partyB) deposits USDC to buy ETH
    function depositUSDC(uint256 amount) external depositReview(partyB.addr) nonReentrant {
        require(amount > 0, "OTC: USDC amount should be > 0");
        usdc.transferFrom(msg.sender, address(this), amount);
        _updatePartyState(msg.sender, true, false, false);

        // Mint Lzybra tokens for the buyer (party B)
        lzybra.mint(msg.sender, amount);  // Assuming 1 USDC = 1 Lzybra

        emit Deposit(msg.sender, amount);
    }

    /// @notice ETH depositor (partyA) deposits ETH to sell for USDC
    function depositETH() external payable depositReview(partyA.addr) nonReentrant {
        require(msg.value > 0, "OTC: ETH amount should be > 0");
        _updatePartyState(msg.sender, true, false, false);
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Party signs the contract
    function signContract() external signingReview nonReentrant {
        _updatePartyState(msg.sender, true, true, false);
        emit Sign(msg.sender);
    }

    /// @notice Withdraw USDC after both parties have signed, burns Lzybra tokens
    function withdrawUSDC() external exchangeReview(partyB.addr) nonReentrant {
        uint256 amount = usdc.balanceOf(address(this));
        require(amount > 0, "OTC: No USDC available for withdrawal");

        // Burn the corresponding amount of Lzybra tokens from party B
        lzybra.burn(msg.sender, amount);

        // Transfer USDC to the buyer (party B)
        usdc.transfer(msg.sender, amount);
        _updatePartyState(msg.sender, true, true, true);
        emit Withdraw(msg.sender, amount);

        if (partyA.signed && partyA.deposited && !partyA.rescinded) {
            selfdestruct(payable(partyA.addr));
        }
    }

    /// @notice Withdraw ETH after both parties have signed
    function withdrawETH() external exchangeReview(partyA.addr) nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "OTC: No ETH available for withdrawal");

        payable(msg.sender).transfer(amount);
        _updatePartyState(msg.sender, true, true, true);
        emit Withdraw(msg.sender, amount);

        if (partyB.signed && partyB.deposited && !partyB.rescinded) {
            selfdestruct(payable(partyB.addr));
        }
    }

    /// @notice Rescind the contract and return deposits
    function rescindContractA() external rescindReview(partyA.addr) nonReentrant {
        _returnDeposits();
    }

    /// @notice Rescind the contract and return deposits
    function rescindContractB() external rescindReview(partyB.addr) nonReentrant {
        _returnDeposits();
    }

    function _returnDeposits() internal {
        // Return USDC to partyB
        uint256 usdcAmount = usdc.balanceOf(address(this));
        usdc.transfer(partyB.addr, usdcAmount);

        // Return ETH to partyA
        uint256 ethAmount = address(this).balance;
        payable(partyA.addr).transfer(ethAmount);

        selfdestruct(payable(address(0)));
    }

    function _initContract(
        address _partyA,
        address _partyB,
        uint256 _depositTime,
        uint256 _signingTime
    ) internal {
        partyA = Party(_partyA, false, false, false);
        partyB = Party(_partyB, false, false, false);
        periods = Periods(_depositTime, _signingTime);
    }

    function _updatePartyState(
        address _party,
        bool _deposited,
        bool _signed,
        bool _rescinded
    ) internal {
        parties[_party].deposited = _deposited;
        parties[_party].signed = _signed;
        parties[_party].rescinded = _rescinded;
    }
}
