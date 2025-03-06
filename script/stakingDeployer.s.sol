// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StableLzybraSwap} from "../src/StableLzybraSwap.sol";
import {ZFIStakingLiquidation} from "../src/ZybraStaking.sol";
import {ZFI} from "../src/token/ZFI.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract DeploymentScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Contract addresses from existing deployment
        address USDC = 0x8f87BFdd966FfaF1DF9B305AcE736C5Cc9BecfD6;
        address ZRUSD = 0xB68dD3583390065C67626701052524Dbd7238246;
        address USDC_PRICE_FEED = 0x0A9bf1b4D649D52172d4077CD4a3b71E39d6C242;
        address FEE_COLLECTOR = msg.sender; // Or specify another address

        // Deploy StableLzybraSwap Implementation and Proxy
        StableLzybraSwap stableLzybraImpl = new StableLzybraSwap();
        
        bytes memory data = abi.encodeWithSelector(
            StableLzybraSwap.initialize.selector,
            USDC,
            ZRUSD,
            USDC_PRICE_FEED,
            FEE_COLLECTOR
        );
        
        ERC1967Proxy stableLzybraProxy = new ERC1967Proxy(
            address(stableLzybraImpl),
            data
        );
        StableLzybraSwap stableLzybra = StableLzybraSwap(payable(address(stableLzybraProxy)));
        ZFI ZFI_TOKEN = new ZFI("ZybraFinance", "ZFI");
        ZFI_TOKEN.grantMintRole(msg.sender);
        ZFI_TOKEN.mint(msg.sender, 1000000000000000000000000);
        // Additional contract addresses needed for staking
        address NVIDIA_TOKEN = 0xAE17F574E0E5f8B04f4b9a296658D3E7890fc53A;
        address NVIDIA_PRICE_FEED = 0x6ea85Bab4D5d024d053D0a18E56d6662AA93bF3C;
        
        // Deploy ZFIStakingLiquidation

// Deploy Implementation and Proxy
ZFIStakingLiquidation stakingImplementation = new ZFIStakingLiquidation();

// Prepare initialization data
bytes memory initData = abi.encodeWithSelector(
    ZFIStakingLiquidation.initialize.selector,
    IERC20(address(ZFI_TOKEN)),  // ZFI token
    address(0x930D98E0a88a1BD38ee0583a0AcaFD72eb0C41c6),  // ZybraVault Proxy
    StableLzybraSwap(payable(address(stableLzybraProxy))),
    ISwapRouter(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4),  // UniswapRouter
    address(NVIDIA_TOKEN)  // WETH address
);

// Deploy proxy with implementation
ERC1967Proxy stakingProxy = new ERC1967Proxy(
    address(stakingImplementation),
    initData
);

// Get instance of proxy with implementation ABI
ZFIStakingLiquidation staking = ZFIStakingLiquidation(payable(address(stakingProxy)));

console.log("ZFIStakingLiquidation Implementation:", address(stakingImplementation));
console.log("ZFIStakingLiquidation Proxy:", address(stakingProxy));

IERC20(address(ZFI_TOKEN)).approve(address(staking), 100*10**18
);
staking.stake( 100*10**18);
staking.unstake( 100*10**18);
        // Log deployment addresses
        console.log("StableLzybraSwap Implementation deployed at:", address(stableLzybraImpl));
        console.log("StableLzybraSwap Proxy deployed at:", address(stableLzybraProxy));
        console.log("ZFIStakingLiquidation deployed at:", address(staking));


        vm.stopBroadcast();
    }
}