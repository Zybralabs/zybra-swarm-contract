// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Gateway} from "../src/gateway/Gateway.sol";
import {GasService} from "../src/gateway/GasService.sol";
import {IAuth} from "../src/interfaces/IAuth.sol";

import {MockSafe} from "../../test/mocks/MockSafe.sol";
import "forge-std/Script.sol";

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;
    address adminSafe;
    address[] adapters;

    Gateway public gateway;
    GasService public gasService;


    function deploy(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );

        uint64 messageCost = uint64(vm.envOr("MESSAGE_COST", uint256(20000000000000000))); // in Weight
        uint64 proofCost = uint64(vm.envOr("PROOF_COST", uint256(20000000000000000))); // in Weigth
        uint128 gasPrice = uint128(vm.envOr("GAS_PRICE", uint256(2500000000000000000))); // Centrifuge Chain
        uint256 tokenPrice = vm.envOr("TOKEN_PRICE", uint256(178947400000000)); // CFG/ETH

      
        gasService = new GasService(messageCost, proofCost, gasPrice, tokenPrice);
         
        _endorse();
        _rely();
        _file();
    }

    function _endorse() internal {
    }

    function _rely() internal {
        // Rely on PoolManager


        // Rely on Root
    
        // Rely on guardian

        // Rely on gateway

        // Rely on others
    }

    function _file() public {

    }

    function wire(address adapter) public {
        adapters.push(adapter);
        gateway.file("adapters", adapters);
    }

    function removeDeployerAccess(address adapter, address deployer) public {
        gateway.deny(deployer);
        gasService.deny(deployer);
    }
}
