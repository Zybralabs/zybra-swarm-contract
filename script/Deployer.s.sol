// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/DotcManagerV2.sol";
import "../src/DotcV2.sol";
import "../src/token/ERC20.sol";
import "../src/LZybraSwarmVaultV1.sol";
import "../src/token/LZYBRA.sol";
import "../src/AssetTokenFactory.sol";
import "../src/AssetTokenData.sol";
import "../src/AssetToken.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "../src/configuration/ZybraConfigurator.sol";
import "test/mocks/MockAdapter.sol";
import "test/mocks/MockSafe.sol";
import "../src/mocks/chainLinkMock.sol";

contract DeploymentScript is Script {
    function run() external {
        // Load the deployer's private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy MockSafe
        address;
        pausers[0] = msg.sender;
        MockSafe mockSafe = new MockSafe(pausers, 1);
        console.log("MockSafe deployed at:", address(mockSafe));

        // Step 2: Deploy Mock Adapters
        MockAdapter adapter1 = new MockAdapter(msg.sender);
        MockAdapter adapter2 = new MockAdapter(msg.sender);
        MockAdapter adapter3 = new MockAdapter(msg.sender);

        adapter1.setReturn("estimate", 1 gwei);
        adapter2.setReturn("estimate", 1.25 gwei);
        adapter3.setReturn("estimate", 1.75 gwei);

        console.log("Adapters deployed at:", address(adapter1), address(adapter2), address(adapter3));

        // Step 3: Deploy ERC20 (USDC)
        ERC20 usdc = new ERC20(6);
        usdc.file("name", "X's Dollar");
        usdc.file("symbol", "USDX");
        console.log("USDC deployed at:", address(usdc));

        // Step 4: Deploy Asset Token Factory and Asset Tokens
        AssetTokenData assetTokenData = new AssetTokenData(0);
        AssetTokenFactory assetTokenFactory = new AssetTokenFactory();
        assetTokenFactory.initialize(address(assetTokenData));

        address issuer = address(0x123);
        address guardian = address(0x456);

        AssetToken asset1 = AssetToken(
            assetTokenFactory.deployAssetToken(
                issuer, guardian, 0.5 ether, "ipfs://tbd", 1 ether, "NVIDIA", "NVIDIA"
            )
        );
        AssetToken asset2 = AssetToken(
            assetTokenFactory.deployAssetToken(
                issuer, guardian, 0.5 ether, "ipfs://tbd", 1 ether, "MCSF", "MCSF"
            )
        );
        AssetToken asset3 = AssetToken(
            assetTokenFactory.deployAssetToken(
                issuer, guardian, 0.5 ether, "ipfs://tbd", 1 ether, "TESLA", "TESLA"
            )
        );

        console.log("Asset Tokens deployed at:", address(asset1), address(asset2), address(asset3));

        // Step 5: Deploy Chainlink Mock Price Feeds
        mockChainlink chainLinkMockUSDC = new mockChainlink();
        mockChainlink chainLinkMockNVIDIA = new mockChainlink();
        mockChainlink chainLinkMockMSCRF = new mockChainlink();

        chainLinkMockUSDC.setPrice(1e18);
        chainLinkMockNVIDIA.setPrice(8e18);
        chainLinkMockMSCRF.setPrice(10e18);

        console.log(
            "Chainlink mocks deployed at:",
            address(chainLinkMockUSDC),
            address(chainLinkMockNVIDIA),
            address(chainLinkMockMSCRF)
        );

        // Step 6: Deploy DOTC Manager and DOTC V2
        DotcManagerV2 dotcManager = new DotcManagerV2();
        dotcManager.initialize(msg.sender);

        DotcV2 dotcV2 = new DotcV2();
        dotcV2.initialize(dotcManager);

        console.log("DOTC Manager and DOTC V2 deployed at:", address(dotcManager), address(dotcV2));

        // Step 7: Deploy Mock Pyth
        MockPyth mockPyth = new MockPyth(3600, 0.01 ether); // Example valid time and fee
        console.log("MockPyth deployed at:", address(mockPyth));

        // Step 8: Deploy Zybra Configurator
        ZybraConfigurator configurator = new ZybraConfigurator(msg.sender, address(usdc));
        console.log("Zybra Configurator deployed at:", address(configurator));

        // Step 9: Deploy Lzybra and LzybraVault
        Lzybra lzybra = new Lzybra("Lzybra", "LZYB");
        LzybraVault lzybraVault = new LzybraVault(
            address(lzybra),
            address(dotcV2),
            address(usdc),
            msg.sender,
            address(configurator),
            address(mockPyth)
        );

        lzybra.grantMintRole(address(lzybraVault));
        configurator.setMintVaultMaxSupply(address(lzybraVault), 200_000_000 * 10**18);
        console.log("Lzybra and LzybraVault deployed at:", address(lzybra), address(lzybraVault));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
