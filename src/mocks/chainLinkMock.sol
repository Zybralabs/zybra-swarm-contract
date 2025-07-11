// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract mockChainlink {
    uint256 price = 1*1e18;

    function setPrice(uint256 _price) external {
        price = _price;
    }
    function latestRoundData() external view returns(uint80, int, uint, uint, uint80) {
        return (0, int(price), 0,0,0);
    }
    function fetchPrice() external returns(uint256) {
        return price;
    }
}