// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {BurnMintERC677} from "../../node_modules/@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/BurnMintERC677.sol";
contract Lzybra is BurnMintERC677 {
   constructor(
        string memory name,
        string memory symbol
    ) BurnMintERC677(name, symbol, 18, 10000000000000 * 10**18) {}
}
