// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title  ERC20
/// @notice Standard ERC-20 implementation, with mint/burn functionality.
/// @dev    Requires allowance even when from == msg.sender, to mimic
///         USDC and the OpenZeppelin ERC20 implementation.
contract MockUSDC is ERC20 {
  uint8 private immutable _decimals;

    constructor(uint8 decimals_) ERC20("ERC20", "20") {
        _decimals = decimals_;
        _mint(msg.sender, 1000 * 10 ** decimals_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint amount) public {
        _mint(to, amount * 10 ** decimals());
    }
}
