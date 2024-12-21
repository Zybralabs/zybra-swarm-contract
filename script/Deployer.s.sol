// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/ERC20.sol";
import {Lzybra} from "../src/token/LZYBRA.sol";
import {AssetTokenData} from "../src/AssetTokenData.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {AssetTokenFactory} from  "../src/AssetTokenFactory.sol";
import {LzybraVault} from "../src/LZybraSwarmVaultV1.sol";
import {ZybraConfigurator} from "../src/configuration/ZybraConfigurator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DotcManagerV2} from "../src/DotcManagerV2.sol";
import {DotcV2} from  "../src/DotcV2.sol";
import "../test/mocks/MockAdapter.sol";
import "../src/mocks/chainLinkMock.sol";
import "../test/mocks/MockSafe.sol";
import "../test/mocks/MockAdapter.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract FullDeployment is Script {
       MockAdapter adapter1;
    MockAdapter adapter2;
    MockAdapter adapter3;
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = msg.sender;

        // Step 1: Deploy MockSafe
       // Step 1: Deploy MockSafe
     address[] memory pausers;
     address[]  memory testAdapters;

  
 // Initialize array
        pausers[0] = deployer; // Assign deployer

address adminSafe = address(new MockSafe(pausers, 1)); // Deploy MockSafe
console.log("MockSafe deployed at:", adminSafe); // Log address


        // Step 2: Deploy USDC (Mock ERC20 Token)
        ERC20 usdc = new ERC20(6);
        usdc.file("name", "X's Dollar");
        usdc.file("symbol", "USDX");
        console.log("USDC deployed at:", address(usdc));

        // Step 3: Deploy AssetTokenData and AssetTokenFactory
        AssetTokenData assetTokenData = new AssetTokenData(0);
        AssetTokenFactory assetTokenFactory = new AssetTokenFactory();
        assetTokenFactory.initialize(address(assetTokenData));
        console.log("AssetTokenData deployed at:", address(assetTokenData));
        console.log("AssetTokenFactory deployed at:", address(assetTokenFactory));

        // Step 4: Deploy AssetTokens (e.g., NVIDIA, MCSF, TESLA)
        AssetToken asset1 = AssetToken(
            assetTokenFactory.deployAssetToken(
                deployer,
                deployer,
                5e17,
                "ipfs://tbd",
                1e18,
                "NVIDIA",
                "NVIDIA"
            )
        );
        AssetToken asset2 = AssetToken(
            assetTokenFactory.deployAssetToken(
                deployer,
                deployer,
                5e17,
                "ipfs://tbd",
                1e18,
                "MCSF",
                "MCSF"
            )
        );
        AssetToken asset3 = AssetToken(
            assetTokenFactory.deployAssetToken(
                deployer,
                deployer,
                5e17,
                "ipfs://tbd",
                1e18,
                "TESLA",
                "TESLA"
            )
        );
        console.log("AssetToken NVIDIA deployed at:", address(asset1));
        console.log("AssetToken MCSF deployed at:", address(asset2));
        console.log("AssetToken TESLA deployed at:", address(asset3));

        // Step 5: Deploy Lzybra Token
        Lzybra lzybra = new Lzybra("Lzybra", "LZYB");
        console.log("Lzybra deployed at:", address(lzybra));

        // Step 6: Deploy MockChainlink Price Feeds
        mockChainlink chainLinkMockUSDC = new mockChainlink();
        mockChainlink chainLinkMockNVIDIA = new mockChainlink();
        mockChainlink chainLinkMockMSCRF = new mockChainlink();
        chainLinkMockUSDC.setPrice(1e18);
        chainLinkMockNVIDIA.setPrice(8e18);
        chainLinkMockMSCRF.setPrice(10e18);
        console.log("Chainlink Mock USDC deployed at:", address(chainLinkMockUSDC));
        console.log("Chainlink Mock NVIDIA deployed at:", address(chainLinkMockNVIDIA));
        console.log("Chainlink Mock MSCRF deployed at:", address(chainLinkMockMSCRF));

        // Step 7: Deploy MockPyth Oracle
        MockPyth mockPyth = new MockPyth(3600, 0.01 ether);
        console.log("MockPyth deployed at:", address(mockPyth));

        // Step 8: Deploy DotcManagerV2 and DotcV2
        DotcManagerV2 dotcManagerV2 = new DotcManagerV2();
        dotcManagerV2.initialize(deployer);
        DotcV2 dotcV2 = new DotcV2();
        dotcV2.initialize(dotcManagerV2);
        console.log("DotcManagerV2 deployed at:", address(dotcManagerV2));
        console.log("DotcV2 deployed at:", address(dotcV2));

        // Step 9: Deploy LzybraConfigurator
          ZybraConfigurator configuratorImplementation = new ZybraConfigurator();
        console.log(
            "ZybraConfigurator Implementation deployed at:",
            address(configuratorImplementation)
        );

        // Step 6: Deploy ZybraConfigurator Proxy
        ERC1967Proxy configuratorProxy = new ERC1967Proxy(
            address(configuratorImplementation),
            abi.encodeWithSelector(
                ZybraConfigurator.initialize.selector,
                address(lzybra),
                address(usdc)
            )
        );
        ZybraConfigurator configurator = ZybraConfigurator(address(configuratorProxy));
        console.log("ZybraConfigurator Proxy deployed at:", address(configurator));

        // Step 7: Deploy LzybraVault Implementation
        LzybraVault lzybraVaultImplementation = new LzybraVault();
        console.log(
            "LzybraVault Implementation deployed at:",
            address(lzybraVaultImplementation)
        );

        // Step 8: Deploy LzybraVault Proxy
        ERC1967Proxy lzybraVaultProxy = new ERC1967Proxy(
            address(lzybraVaultImplementation),
            abi.encodeWithSelector(
                LzybraVault.initialize.selector,
                address(usdc),
                address(lzybra),
                address(dotcV2),
                address(configurator),
                address(usdc), // Chainlink Price Feed Address
                address(mockPyth)
            )
        );
        LzybraVault lzybraVault = LzybraVault(address(lzybraVaultProxy));
        console.log("LzybraVault Proxy deployed at:", address(lzybraVault));

        lzybra.grantMintRole(address(lzybraVault));



        console.log("System fully deployed!");

        vm.stopBroadcast();
    }
}
