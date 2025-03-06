// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/token/ERC20.sol";
import "forge-std/console2.sol";
import {Lzybra} from "../src/token/LZYBRA.sol";
import {AssetTokenData} from "../src/AssetTokenData.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {AssetTokenFactory} from "../src/AssetTokenFactory.sol";
import {ZybraVault} from "../src/LZybraSwarmVaultV1.sol";
import {ZybraConfigurator} from "../src/configuration/ZybraConfigurator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Asset, AssetType, AssetPrice, OfferFillType, PercentageType, OfferPrice, OfferStruct, DotcOffer, OnlyManager, OfferPricingType, TakingOfferType} from "../src/structures/DotcStructuresV2.sol";
import {DotcManagerV2} from "../src/DotcManagerV2.sol";
import {DotcV2} from "../src/DotcV2.sol";
import {DotcEscrowV2} from "../src/DotcEscrowV2.sol";
import {AssetHelper} from "../src/helpers/AssetHelper.sol";
import {OfferHelper} from "../src/helpers/OfferHelper.sol";
import {DotcOfferHelper} from "../src/helpers/DotcOfferHelper.sol";
import "../test/mocks/MockAdapter.sol";
import "../src/mocks/chainLinkMock.sol";
import "../test/mocks/MockSafe.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract FullDeployment is Script {
    ERC20 public USDC;
    address adminSafe;
    // AssetToken public asset1;
    // AssetToken public asset2;
    // AssetToken public asset3;

    ERC20 public asset1;
    ERC20 public asset2;
    ERC20 public asset3;

    Lzybra public lzybra;
    ZybraVault public lzybravault;
    ZybraConfigurator public configurator;
    DotcV2 public dotcV2;
    DotcManagerV2 public dotcManagerV2;
    DotcEscrowV2 public escrowContract;
    MockPyth public mockPyth;
    mockChainlink public ChainLinkMockUSDC;
    mockChainlink public ChainLinkMockNVIDIA;
    mockChainlink public ChainLinkMockMSCRF;
    AssetTokenFactory assetTokenFactory;
    // DOTC helper addresses
    address public assetHelper;
    address public offerHelper;
    address public dotcOfferHelper;

    // Mock adapters
    MockAdapter public adapter1;
    MockAdapter public adapter2;
    MockAdapter public adapter3;

    Asset withdrawalAsset1;
    Asset withdrawalAsset2;
    Asset withdrawalAsset3;
    Asset depositAsset;

    OfferStruct offer;
    OfferStruct offer2;
    OfferStruct offer3;
    uint256 offerId;

    uint128 public defaultAssetId = 1;
    uint128 public defaultPrice = 5 * 10 ** 18;
    uint128 public amount = 5 * 10 ** 18;
    uint8 public defaultDecimals = 8;

    uint256 AMOUNT = 100000000e18;

    address[] specialAddress = new address[](4);
    address[] authorizationAddresses = new address[](4);
    function deployDOTCSystem(address deployer) internal {
        // Deploy libraries
        // AssetHelper assetHelperLib =  AssetHelper();
        // assetHelper = address(assetHelperLib);
        // console.log("AssetHelper deployed at:", assetHelper);

        // // Deploy OfferHelper with AssetHelper link
        // OfferHelper offerHelperLib =  OfferHelper();
        // offerHelper = address(offerHelperLib);
        // console.log("OfferHelper deployed at:", offerHelper);

        // // Deploy DotcOfferHelper
        // DotcOfferHelper dotcOfferHelperLib =  DotcOfferHelper();
        // dotcOfferHelper = address(dotcOfferHelperLib);
        // console.log("DotcOfferHelper deployed at:", dotcOfferHelper);

        // Deploy DotcManagerV2 as upgradeable
        DotcManagerV2 dotcManagerImpl = new DotcManagerV2();
        bytes memory dotcManagerData = abi.encodeWithSelector(
            DotcManagerV2.initialize.selector,
            deployer
        );
        ERC1967Proxy dotcManagerProxy = new ERC1967Proxy(
            address(dotcManagerImpl),
            dotcManagerData
        );
        dotcManagerV2 = DotcManagerV2(address(dotcManagerProxy));
        console.log("DotcManagerV2 deployed at:", address(dotcManagerV2));

        // Deploy DotcV2 as upgradeable
        bytes memory assetHelperBytecode = type(AssetHelper).creationCode;
        address assetHelperAddress;
        assembly {
            assetHelperAddress := create(
                0,
                add(assetHelperBytecode, 0x20),
                mload(assetHelperBytecode)
            )
        }
        console.log("AssetHelper deployed at:", assetHelperAddress);

        bytes memory offerHelperBytecode = type(OfferHelper).creationCode;
        address offerHelperAddress;
        assembly {
            offerHelperAddress := create(
                0,
                add(offerHelperBytecode, 0x20),
                mload(offerHelperBytecode)
            )
        }
        console.log("OfferHelper deployed at:", offerHelperAddress);

        bytes memory dotcOfferHelperBytecode = type(DotcOfferHelper)
            .creationCode;
        address dotcOfferHelperAddress;
        assembly {
            dotcOfferHelperAddress := create(
                0,
                add(dotcOfferHelperBytecode, 0x20),
                mload(dotcOfferHelperBytecode)
            )
        }
        console.log("DotcOfferHelper deployed at:", dotcOfferHelperAddress);

        // Run the forge command with these addresses for library linking

        // Deploy implementation contract
        console.log("ASSET_HELPER_ADDRESS=", assetHelperAddress);
        console.log("OFFER_HELPER_ADDRESS=", offerHelperAddress);
        console.log("DOTC_OFFER_HELPER_ADDRESS=", dotcOfferHelperAddress);
        // Deploy proxy
        DotcV2 dotcImpl = new DotcV2();
        ERC1967Proxy dotcProxy = new ERC1967Proxy(
            address(dotcImpl),
            abi.encodeWithSelector(
                DotcV2.initialize.selector,
                address(dotcManagerV2)
            )
        );
        dotcV2 = DotcV2(payable(address(dotcProxy)));

        console.log("DotcV2 proxy deployed at:", address(dotcV2));

        // Prepare initialization data

        // Deploy DotcEscrowV2 as upgradeable
        DotcEscrowV2 escrowImpl = new DotcEscrowV2();
        bytes memory escrowData = abi.encodeWithSelector(
            DotcEscrowV2.initialize.selector,
            address(dotcManagerV2)
        );
        ERC1967Proxy escrowProxy = new ERC1967Proxy(
            address(escrowImpl),
            escrowData
        );
        escrowContract = DotcEscrowV2(payable(address(escrowProxy)));
        console.log("DotcEscrowV2 deployed at:", address(escrowContract));

        // Configure DOTC system
        dotcManagerV2.changeEscrow(escrowContract);
        dotcManagerV2.changeDotc(dotcV2);
        dotcManagerV2.changeDotcInEscrow();
        dotcManagerV2.changeEscrowInDotc();
    }

    // SPDX-License-Identifier: AGPL-3.0-only

    // Public variables that will be accessible to inheriting contracts

    function deploy(address deployer) public virtual {
        // Initialize Foundry's VM cheatcodes for deployment
        // vm.startPrank(deployer);

        // Step 1: Deploy USDC
        USDC = new ERC20(6);
        USDC.file("name", "X's Dollar");
        USDC.file("symbol", "USDX");
        USDC.mint(deployer, 100000 * 10e18);

        // Step 2: Deploy Asset Token System
        AssetTokenData assetTokenData = new AssetTokenData(5);
        AssetTokenFactory assetTokenFactory = new AssetTokenFactory();
        assetTokenFactory.initialize(address(assetTokenData));

        // Deploy Asset Tokens
        // asset1 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e18,
        //         "NVIDIA",
        //         "NVIDIA"
        //     )
        // );
        // asset2 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e18,
        //         "MCSF",
        //         "MCSF"
        //     )
        // );
        // asset3 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e18,
        //         "TESLA",
        //         "TESLA"
        //     )
        // );

        asset1 = new ERC20(18);
        asset2 = new ERC20(18);

        asset3 = new ERC20(18);

        asset1.file("name", "TSLA");

        asset1.file("symbol", "TSLA");
        asset2.file("name", "NVIDIA");

        asset2.file("symbol", "NVIDIA");
        asset3.file("name", "MRCSF");

        asset3.file("symbol", "MRCSF");

        // Mint initial tokens

        // Step 3: Deploy Lzybra Token
        lzybra = new Lzybra("Lzybra", "LZYB");

        // Step 4: Deploy Price Feeds
        ChainLinkMockUSDC = new mockChainlink();
        ChainLinkMockNVIDIA = new mockChainlink();
        ChainLinkMockMSCRF = new mockChainlink();

        ChainLinkMockUSDC.setPrice(1e18);
        ChainLinkMockNVIDIA.setPrice(8e18);
        ChainLinkMockMSCRF.setPrice(10e18);

        // Step 5: Deploy MockPyth
        mockPyth = new MockPyth(3600, 0.01 ether);

        // Step 6: Deploy DOTC System
        // Deploy Manager
        DotcManagerV2 dotcManagerImpl = new DotcManagerV2();
        ERC1967Proxy dotcManagerProxy = new ERC1967Proxy(
            address(dotcManagerImpl),
            abi.encodeWithSelector(DotcManagerV2.initialize.selector, deployer)
        );
        dotcManagerV2 = DotcManagerV2(address(dotcManagerProxy));

        // Deploy DOTC
        DotcV2 dotcImpl = new DotcV2();
        ERC1967Proxy dotcProxy = new ERC1967Proxy(
            address(dotcImpl),
            abi.encodeWithSelector(
                DotcV2.initialize.selector,
                address(dotcManagerV2)
            )
        );
        dotcV2 = DotcV2(payable(address(dotcProxy)));

        // Deploy Escrow
        DotcEscrowV2 escrowImpl = new DotcEscrowV2();
        ERC1967Proxy escrowProxy = new ERC1967Proxy(
            address(escrowImpl),
            abi.encodeWithSelector(
                DotcEscrowV2.initialize.selector,
                address(dotcManagerV2)
            )
        );
        escrowContract = DotcEscrowV2(payable(address(escrowProxy)));

        // Configure DOTC system
        dotcManagerV2.changeEscrow(escrowContract);
        dotcManagerV2.changeDotc(dotcV2);
        dotcManagerV2.changeDotcInEscrow();
        dotcManagerV2.changeEscrowInDotc();

        // Step 7: Deploy Configurator
        ZybraConfigurator configuratorImpl = new ZybraConfigurator();
        ERC1967Proxy configuratorProxy = new ERC1967Proxy(
            address(configuratorImpl),
            abi.encodeWithSelector(
                ZybraConfigurator.initialize.selector,
                address(lzybra),
                address(USDC)
            )
        );
        configurator = ZybraConfigurator(address(configuratorProxy));

        // Step 8: Deploy ZybraVault
        // ZybraVault lzybraVaultImpl = new ZybraVault();
        // ERC1967Proxy vaultProxy = new ERC1967Proxy(
        //     address(lzybraVaultImpl),
        //     abi.encodeWithSelector(
        //         ZybraVault.initialize.selector,
        //         address(USDC),
        //         address(lzybra),
        //         address(dotcV2),
        //         address(configurator),
        //         address(ChainLinkMockUSDC),
        //         bytes32(0x00),
        //         address(mockPyth)
        //     )
        // );
        // lzybravault = ZybraVault(address(vaultProxy));

        ZybraVault lzybravault = new ZybraVault(
            address(USDC),
            address(lzybra),
            address(dotcV2),
            address(configurator),
            address(ChainLinkMockUSDC),
            bytes32(0x00),
            address(mockPyth)
        );
        // ERC1967Proxy vaultProxy = new ERC1967Proxy(
        //     address(lzybraVaultImpl),
        //     abi.encodeWithSelector(
        //         ZybraVault.initialize.selector,
        //         address(USDC),
        //         address(lzybra),
        //         address(dotcV2),
        //         address(configurator),
        //         address(ChainLinkMockUSDC),
        //         bytes32(0x00),
        //         address(mockPyth)
        //     )
        // );
        // lzybravault = ZybraVault(address(vaultProxy));

        // Deploy mock adapters if needed for testing
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY"); // Add second private key to .env

        // Start with deployer
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        address user = vm.addr(userPrivateKey);
        console.log("user", deployer);
        console.log("user", user);
        address[] memory pausers = new address[](1);
        //         pausers[0] = self;
        pausers[0] = msg.sender;
        address adminSafe = address(new MockSafe(pausers, 1));
        console.log("MockSafe deployed at:", adminSafe);

        // Step 2: Deploy USDC (Mock ERC20 Token)
        ERC20 usdc = ERC20(0x15C46bEc4B862BABb386437CECEc9e53e8F4694A);
        usdc.file("name", "X's Dollar");
        usdc.file("symbol", "USDX");
        console.log("USDC deployed at:", address(usdc));
        usdc.mint(deployer, 100000 * 10e18);
        usdc.mint(user, 100000 * 10e18);
        // Step 3: Deploy AssetTokenData and AssetTokenFactory
        // AssetTokenData assetTokenData = new AssetTokenData(5);
        // AssetTokenFactory assetTokenFactory = new AssetTokenFactory();
        // assetTokenFactory.initialize(address(assetTokenData));
        // console.log("AssetTokenData deployed at:", address(assetTokenData));
        // console.log(
        //     "AssetTokenFactory deployed at:",
        //     address(assetTokenFactory)
        // );

        // Step 4: Deploy AssetTokens
        // asset1 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e18,
        //         "NVIDIA",
        //         "NVIDIA"
        //     )
        // );
        // asset2 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e17,
        //         "MCSF",
        //         "MCSF"
        //     )
        // );
        // asset3 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e17,
        //         "TESLA",
        //         "TESLA"
        //     )
        // );

        asset1 = new ERC20(18);
        asset2 = new ERC20(18);

        asset3 = new ERC20(18);

        asset1.file("name", "TSLA");

        asset1.file("symbol", "TSLA");
        asset2.file("name", "NVIDIA");

        asset2.file("symbol", "NVIDIA");
        asset3.file("name", "MRCSF");

        asset3.file("symbol", "MRCSF");

        console.log("AssetToken NVIDIA deployed at:", address(asset1));
        console.log("AssetToken MCSF deployed at:", address(asset2));
        console.log("AssetToken TESLA deployed at:", address(asset3));

        // uint256 mintID1 = asset1.mint(deployer, 100000 * 10e18);

        // // Mint for investor

        // // Mint for user
        // uint256 mintID3 = asset1.requestMint(AMOUNT, deployer);

        // // Repeat for asset2
        // uint256 mintID4 = asset2.mint(deployer, 100000 * 10e18);

        // uint256 mintID6 = asset2.mint(deployer, 100000 * 10e18);

        // // Repeat for asset3
        // uint256 mintID7 = asset3.requestMint(AMOUNT);

        // uint256 mintID9 = asset3.requestMint(AMOUNT, deployer);

        asset1.mint(deployer, 100000 * 10e18);
        asset1.mint(user, 100000 * 10e18);
        asset2.mint(deployer, 100000 * 10e18);
        asset2.mint(user, 100000 * 10e18);
        asset3.mint(deployer, 100000 * 10e18);
        asset3.mint(user, 100000 * 10e18);

        console.log("Mint ID NVIDIA:", asset1.balanceOf(deployer));
        console.log("Mint ID MCSF:", asset2.balanceOf(deployer));
        console.log("Mint ID TESLA:", asset3.balanceOf(deployer));

        // Step 5: Deploy Lzybra Token
        Lzybra lzybra = Lzybra(0xBcf5a240fF41DdCC06E4e381D389be34F839E798);
        console.log("Lzybra deployed at:", address(lzybra));

        // Step 6: Deploy MockChainlink Price Feeds
        mockChainlink chainLinkMockUSDC = new mockChainlink();
        mockChainlink chainLinkMockNVIDIA = new mockChainlink();
        mockChainlink chainLinkMockMSCRF = new mockChainlink();
        chainLinkMockUSDC.setPrice(1e8);
        chainLinkMockNVIDIA.setPrice(800e8);
        chainLinkMockMSCRF.setPrice(10e8);
        console.log(
            "Chainlink Mock USDC deployed at:",
            address(chainLinkMockUSDC)
        );
        console.log(
            "Chainlink Mock NVIDIA deployed at:",
            address(chainLinkMockNVIDIA)
        );
        console.log(
            "Chainlink Mock MSCRF deployed at:",
            address(chainLinkMockMSCRF)
        );

        // Step 7: MockPyth Oracle address
        address mockPyth = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;
        console.log("MockPyth at:", mockPyth);

        // Step 8: Deploy DOTC System
        deployDOTCSystem(deployer);

        // Step 9: Deploy LzybraConfigurator
        ZybraConfigurator configuratorImplementation = new ZybraConfigurator();
        console.log(
            "ZybraConfigurator Implementation deployed at:",
            address(configuratorImplementation)
        );

        // Step 10: Deploy ZybraConfigurator Proxy
        ERC1967Proxy configuratorProxy = new ERC1967Proxy(
            address(configuratorImplementation),
            abi.encodeWithSelector(
                ZybraConfigurator.initialize.selector,
                address(lzybra),
                address(usdc)
            )
        );
        ZybraConfigurator configurator = ZybraConfigurator(
            address(configuratorProxy)
        );
        console.log(
            "ZybraConfigurator Proxy deployed at:",
            address(configurator)
        );

        // Step 11: Deploy ZybraVault Implementation
        // Step 8: Deploy ZybraVault
        // ZybraVault lzybraVaultImpl = new ZybraVault();
        // ERC1967Proxy vaultProxy = new ERC1967Proxy(
        //     address(lzybraVaultImpl),
        //     abi.encodeWithSelector(
        //         ZybraVault.initialize.selector,
        //         address(USDC),
        //         address(lzybra),
        //         address(dotcV2),
        //         address(configurator),
        //         address(ChainLinkMockUSDC),
        //         bytes32(0x00),
        //         address(mockPyth)
        //     )
        // );
        // lzybravault = ZybraVault(address(vaultProxy));

        ZybraVault lzybraVault = new ZybraVault(
            address(usdc),
            address(lzybra),
            address(dotcV2),
            address(configurator),
            address(chainLinkMockUSDC),
            bytes32(0x00),
            address(mockPyth)
        );
        console.log("ZybraVault Proxy deployed at:", address(lzybraVault));

        specialAddress[0] = deployer;
        specialAddress[1] = deployer;
        specialAddress[2] = deployer;
        specialAddress[3] = deployer;

        authorizationAddresses[0] = deployer;
        authorizationAddresses[1] = deployer;
        authorizationAddresses[2] = deployer;
        authorizationAddresses[3] = deployer;

        // Step 13: Configure oracles and permissions
        lzybraVault.setAssetOracles(
            address(asset1),
            address(chainLinkMockNVIDIA),
            bytes32(0x00)
        );
        lzybraVault.setAssetOracles(
            address(asset2),
            address(chainLinkMockMSCRF),
            bytes32(0x00)
        );
        lzybra.grantMintRole(address(lzybraVault));

        console.log("System fully deployed!");

        depositAsset = Asset({
            assetType: AssetType.ERC20, // Assuming assetType 0 represents some standard like ERC20
            assetAddress: address(usdc), // Example deposit asset address
            amount: defaultPrice, // Example deposit amount
            tokenId: 0, // No specific tokenId for this asset (since it's not an NFT)
            assetPrice: AssetPrice(address(chainLinkMockUSDC), 0, 0) // Example price feed tuple
        });

        withdrawalAsset1 = Asset({
            assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
            assetAddress: address(asset1), // Example withdrawal asset address
            amount: defaultPrice * 3, // Example withdrawal amount
            tokenId: 0, // No tokenId for the withdrawal asset
            assetPrice: AssetPrice(address(chainLinkMockNVIDIA), 0, 0) // Example price feed tuple
        });

        withdrawalAsset2 = Asset({
            assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
            assetAddress: address(asset2), // Example withdrawal asset address
            amount: defaultPrice * 2, // Example withdrawal amount
            tokenId: 0, // No tokenId for the withdrawal asset
            assetPrice: AssetPrice(address(chainLinkMockNVIDIA), 0, 0) // Example price feed tuple
        });

        withdrawalAsset3 = Asset({
            assetType: AssetType.ERC20, // Assuming assetType 1 represents ERC20 or another type
            assetAddress: address(asset3), // Example withdrawal asset address
            amount: defaultPrice * 4, // Example withdrawal amount
            tokenId: 0, // No tokenId for the withdrawal asset
            assetPrice: AssetPrice(address(chainLinkMockMSCRF), 0, 0) // Example price feed tuple
        });

        // Fix: Dynamically initialize the array
        offer = OfferStruct({
            takingOfferType: TakingOfferType.NoType,
            offerPrice: OfferPrice({
                offerPricingType: OfferPricingType.FixedPricing,
                unitPrice: 0,
                percentage: 100,
                percentageType: PercentageType.NoType
            }),
            specialAddresses: specialAddress, // Initialize empty array with size 2
            authorizationAddresses: authorizationAddresses, // Initialize empty array with size 3
            expiryTimestamp: block.timestamp + 2 days,
            timelockPeriod: 0,
            terms: "tbd",
            commsLink: "tbd"
        });

        // Repeat the process for the second offer

        offer2 = OfferStruct({
            takingOfferType: TakingOfferType.NoType,
            offerPrice: OfferPrice({
                offerPricingType: OfferPricingType.FixedPricing,
                unitPrice: 0,
                percentage: 100,
                percentageType: PercentageType.NoType
            }),
            specialAddresses: specialAddress, // Initialize array with 2 addresses
            authorizationAddresses: authorizationAddresses, // Initialize array with 2 addresses
            expiryTimestamp: block.timestamp + 2 days,
            timelockPeriod: 0,
            terms: "tbd",
            commsLink: "tbd"
        });

        offer3 = OfferStruct({
            takingOfferType: TakingOfferType.NoType,
            offerPrice: OfferPrice({
                offerPricingType: OfferPricingType.FixedPricing,
                unitPrice: 0,
                percentage: 100,
                percentageType: PercentageType.NoType
            }),
            specialAddresses: specialAddress, // Initialize array with 2 addresses
            authorizationAddresses: authorizationAddresses, // Initialize array with 2 addresses
            expiryTimestamp: block.timestamp + 2 days,
            timelockPeriod: 0,
            terms: "tbd",
            commsLink: "tbd"
        });

        console.log("Offers created!");
           usdc.approve(address(dotcV2), 100000 * 10e18);
    asset1.approve(address(dotcV2), 100000 * 10e18);
    asset2.approve(address(dotcV2), 100000 * 10e18);
    asset3.approve(address(dotcV2), 100000 * 10e18);
    
    // Create and make offers in DOTC
    console.log("Creating offers in DOTC...");
    dotcV2.makeOffer(withdrawalAsset1, depositAsset, offer);   // OfferId 1
    dotcV2.makeOffer(withdrawalAsset2, depositAsset, offer2);  // OfferId 2
    dotcV2.makeOffer(withdrawalAsset3, depositAsset, offer3);  // OfferId 3
    dotcV2.makeOffer(depositAsset, withdrawalAsset1, offer);   // OfferId 4
    dotcV2.makeOffer(depositAsset, withdrawalAsset2, offer2);  // OfferId 5
    dotcV2.makeOffer(depositAsset, withdrawalAsset3, offer3);  // OfferId 6
    console.log("Created 6 offers in DOTC");
    
    // Configure permissions for ZybraVault
    configurator.setMintVaultMaxSupply(address(lzybraVault), 1000000000e18);
    lzybra.grantMintRole(address(lzybraVault));
    lzybra.grantBurnRole(address(lzybraVault));
    
    // Setup approvals for ZybraVault
    usdc.approve(address(lzybraVault), 100000 * 10e18);
    lzybra.approve(address(lzybraVault), 100000 * 10e18);
    
    console.log("\n----- DEPLOYER: Regular deposit with Asset -----");
    // Deposit using regular deposit method with Asset parameter
    uint256 depositAmount = 10000 * 10**6; // 10,000 USDC (6 decimals)
    uint256 mintAmount = 100 * 10**18;    // 100 ZRusd (18 decimals)
    lzybraVault.deposit(depositAmount, withdrawalAsset1, offer, mintAmount);
    console.log("Regular deposit completed");
    
    console.log("\n----- DEPLOYER1: Deposit with OfferId -----");
    // Deposit using depositWithOfferId
    depositAmount = 5000 * 10**6; // 5,000 USDC
    mintAmount = 50 * 10**18;    // 50 ZRusd
    uint256 offerId = 1; // Using OfferId 4: depositAsset → withdrawalAsset1
    
    // Get basic info about the offer
    (, , Asset memory offerDepositAsset, Asset memory offerWithdrawalAsset, ) = dotcV2.allOffers(offerId);
    console.log("Deposit with OfferId:", offerId);
    console.log("  Deposit asset:", address(offerDepositAsset.assetAddress));
    console.log("  Withdrawal asset:", address(offerWithdrawalAsset.assetAddress));
    
    // Use depositWithOfferId (assuming USDC is the withdraw asset in this offer)
    bool isDynamic = false;
    uint256 maxRate = 0; // Not using rate limit for fixed pricing
    lzybraVault.depositWithOfferId(depositAmount, offerId, mintAmount, isDynamic, maxRate);
    console.log("Deposit with OfferId completed");
    
    console.log("\n----- DEPLOYER: Withdraw with Asset -----");
    // Check user's asset balance
    uint256 userVaultAsset1 = lzybraVault.userAssets(deployer, address(asset1));
    console.log("Current asset1 balance:", userVaultAsset1);
    
    // Withdraw using regular withdraw method
    uint256 withdrawAmount = userVaultAsset1 / 4; // Withdraw 25% of available assets
    lzybraVault.withdraw(withdrawAmount, offerWithdrawalAsset, offer);
    console.log("Regular withdrawal completed, withdraw amount:", withdrawAmount);
    
    console.log("\n----- DEPLOYER: Withdraw with OfferId -----");
    // Withdraw using withdrawWithOfferId
    offerId = 1; // Using OfferId 1: withdrawalAsset1 → depositAsset
    (, , Asset memory withdrawDepositAsset, Asset memory withdrawWithdrawalAsset, ) = dotcV2.allOffers(offerId);
    
    withdrawAmount = userVaultAsset1 / 10; // Withdraw 10% of original balance
    uint256 burnAmount = 5 * 10**18; // Amount of ZRusd to burn during withdrawal
    isDynamic = false;
    maxRate = 0; // Not using rate limit for fixed pricing
    
    lzybraVault.withdrawWithOfferId(offerId, withdrawAmount, burnAmount, maxRate, isDynamic);
    console.log("Withdraw with OfferId completed");
    
    vm.stopBroadcast();
    
    // Now switch to user account
    vm.startBroadcast(userPrivateKey);
    console.log("\n----- USER: Setting up approvals -----");
    
    // Setup approvals for user
    usdc.approve(address(dotcV2), 100000 * 10e18);
    asset1.approve(address(dotcV2), 100000 * 10e18);
    asset2.approve(address(dotcV2), 100000 * 10e18);
    asset3.approve(address(dotcV2), 100000 * 10e18);
    
    usdc.approve(address(lzybraVault), 100000 * 10e18);
    lzybra.approve(address(lzybraVault), 100000 * 10e18);
    
    console.log("\n----- USER: Regular deposit with Asset -----");
    depositAmount = 5000 * 10**6; // 5,000 USDC
    mintAmount = 50 * 10**18;    // 50 ZRusd
    lzybraVault.deposit(depositAmount, withdrawalAsset2, offer2, mintAmount);
    console.log("Regular deposit completed");
    
    console.log("\n----- USER: Deposit with OfferId -----");
    depositAmount = 2500 * 10**6; // 2,500 USDC
    mintAmount = 25 * 10**18;    // 25 ZRusd
    offerId = 5; // Using OfferId 5: depositAsset → withdrawalAsset2
    
    // Use depositWithOfferId
    isDynamic = true; // Try dynamic pricing for user
    maxRate = 0; // 20% above current rate
    lzybraVault.depositWithOfferId(depositAmount, offerId, mintAmount, isDynamic, maxRate);
    console.log("Deposit with OfferId completed");
    
    console.log("\n----- USER: Withdraw with Asset -----");
    // Check user's asset balance
    uint256 userVaultAsset2 = lzybraVault.userAssets(user, address(asset2));
    console.log("Current asset2 balance:", userVaultAsset2);
    
    // Withdraw using regular withdraw method
    withdrawAmount = userVaultAsset2 / 3; // Withdraw 33% of available assets
    lzybraVault.withdraw(withdrawAmount, withdrawalAsset2, offer2);
    console.log("Regular withdrawal completed, withdraw amount:", withdrawAmount);
    
    console.log("\n----- USER: Withdraw with OfferId -----");
    // Withdraw using withdrawWithOfferId
    offerId = 2; // Using OfferId 2: withdrawalAsset2 → depositAsset
    
    withdrawAmount = userVaultAsset2 / 10; // Withdraw 10% of original balance
    burnAmount = 2 * 10**18; // Amount of ZRusd to burn during withdrawal
    isDynamic = true;
    maxRate = 1200 * 10**8; // 20% above current rate
    
    lzybraVault.withdrawWithOfferId(offerId, withdrawAmount, burnAmount, maxRate, isDynamic);
    console.log("Withdraw with OfferId completed");
    
    // Clean up test - claim offers
    console.log("\n----- Claim offers and finalize -----");
    bytes[] memory emptyBytesArray = new bytes[](1);
    emptyBytesArray[0] = "";
    
    // Claim any pending offers if needed
    lzybraVault.claimOffer(6, 0, emptyBytesArray);
    console.log("Claimed offer 6");
    
    // Print final balances
    console.log("\n----- Final balances -----");
    console.log("User USDC balance:", usdc.balanceOf(user));
    console.log("User asset2 balance:", asset2.balanceOf(user));
    console.log("User ZRusd balance:", lzybra.balanceOf(user));
    
    vm.stopBroadcast();
    }

    function testrun() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = address(this);
        console.log(deployer);
        console.log("thisis", address(this));
        address[] memory pausers = new address[](1);
        //         pausers[0] = self;
        pausers[0] = address(this);
        address adminSafe = address(new MockSafe(pausers, 1));
        console.log("MockSafe deployed at:", adminSafe);

        // Step 2: Deploy USDC (Mock ERC20 Token)
        ERC20 usdc = new ERC20(6);
        usdc.file("name", "X's Dollar");
        usdc.file("symbol", "USDX");
        console.log("USDC deployed at:", address(usdc));
        usdc.mint(deployer, 100000 * 10e18);
        // Step 3: Deploy AssetTokenData and AssetTokenFactory
        // AssetTokenData assetTokenData = new AssetTokenData(5);
        // AssetTokenFactory assetTokenFactory = new AssetTokenFactory();
        // assetTokenFactory.initialize(address(assetTokenData));
        // console.log("AssetTokenData deployed at:", address(assetTokenData));
        // console.log(
        //     "AssetTokenFactory deployed at:",
        //     address(assetTokenFactory)
        // );

        // Step 4: Deploy AssetTokens
        // asset1 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e18,
        //         "NVIDIA",
        //         "NVIDIA"
        //     )
        // );
        // asset2 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e17,
        //         "MCSF",
        //         "MCSF"
        //     )
        // );
        // asset3 = AssetToken(
        //     assetTokenFactory.deployAssetToken(
        //         deployer,
        //         deployer,
        //         5e17,
        //         "ipfs://tbd",
        //         1e17,
        //         "TESLA",
        //         "TESLA"
        //     )
        // );

        asset1 = new ERC20(18);
        asset2 = new ERC20(18);

        asset3 = new ERC20(18);

        asset1.file("name", "TSLA");

        asset1.file("symbol", "TSLA");
        asset2.file("name", "NVIDIA");

        asset2.file("symbol", "NVIDIA");
        asset3.file("name", "MRCSF");

        asset3.file("symbol", "MRCSF");
        console.log("AssetToken NVIDIA deployed at:", address(asset1));
        console.log("AssetToken MCSF deployed at:", address(asset2));
        console.log("AssetToken TESLA deployed at:", address(asset3));
        // uint256 mintID1 = asset1.requestMint(100 * 10 ** 18);
        // uint256 mintID2 = asset2.requestMint(100 * 10 ** 18);
        // uint256 mintID3 = asset3.requestMint(100 * 10 ** 18);

        console.log("Mint ID NVIDIA:", asset1.balanceOf(deployer));
        console.log("Mint ID MCSF:", asset2.balanceOf(deployer));
        console.log("Mint ID TESLA:", asset3.balanceOf(deployer));
        // Step 5: Deploy Lzybra Token
        Lzybra lzybra = new Lzybra("Lzybra", "LZYB");
        console.log("Lzybra deployed at:", address(lzybra));

        // Step 6: Deploy MockChainlink Price Feeds
        mockChainlink chainLinkMockUSDC = new mockChainlink();
        mockChainlink chainLinkMockNVIDIA = new mockChainlink();
        mockChainlink chainLinkMockMSCRF = new mockChainlink();
        chainLinkMockUSDC.setPrice(1e18);
        chainLinkMockNVIDIA.setPrice(800e18);
        chainLinkMockMSCRF.setPrice(10e18);
        console.log(
            "Chainlink Mock USDC deployed at:",
            address(chainLinkMockUSDC)
        );
        console.log(
            "Chainlink Mock NVIDIA deployed at:",
            address(chainLinkMockNVIDIA)
        );
        console.log(
            "Chainlink Mock MSCRF deployed at:",
            address(chainLinkMockMSCRF)
        );

        // Step 7: MockPyth Oracle address
        address mockPyth = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;
        console.log("MockPyth at:", mockPyth);

        // Step 8: Deploy DOTC System
        deployDOTCSystem(deployer);

        // Step 9: Deploy LzybraConfigurator
        ZybraConfigurator configuratorImplementation = new ZybraConfigurator();
        console.log(
            "ZybraConfigurator Implementation deployed at:",
            address(configuratorImplementation)
        );

        // Step 10: Deploy ZybraConfigurator Proxy
        ERC1967Proxy configuratorProxy = new ERC1967Proxy(
            address(configuratorImplementation),
            abi.encodeWithSelector(
                ZybraConfigurator.initialize.selector,
                address(lzybra),
                address(usdc)
            )
        );
        ZybraConfigurator configurator = ZybraConfigurator(
            address(configuratorProxy)
        );
        console.log(
            "ZybraConfigurator Proxy deployed at:",
            address(configurator)
        );

        // Step 11: Deploy ZybraVault Implementation
        // Step 8: Deploy ZybraVault
        // ZybraVault lzybraVaultImpl = new ZybraVault();
        // ERC1967Proxy vaultProxy = new ERC1967Proxy(
        //     address(lzybraVaultImpl),
        //     abi.encodeWithSelector(
        //         ZybraVault.initialize.selector,
        //         address(USDC),
        //         address(lzybra),
        //         address(dotcV2),
        //         address(configurator),
        //         address(ChainLinkMockUSDC),
        //         bytes32(0x00),
        //         address(mockPyth)
        //     )
        // );
        // lzybravault = ZybraVault(address(vaultProxy));

        ZybraVault lzybraVault = new ZybraVault(
            address(USDC),
            address(lzybra),
            address(dotcV2),
            address(configurator),
            address(ChainLinkMockUSDC),
            bytes32(0x00),
            address(mockPyth)
        );
        console.log("ZybraVault Proxy deployed at:", address(lzybraVault));

        // Step 13: Configure oracles and permissions
        lzybraVault.setAssetOracles(
            address(asset1),
            address(chainLinkMockNVIDIA),
            0xb1073854ed24cbc755dc527418f52b7d271f6cc967bbf8d8129112b18860a593
        );
        lzybraVault.setAssetOracles(
            address(asset2),
            address(chainLinkMockMSCRF),
            0xd0ca23c1cc005e004ccf1db5bf76aeb6a49218f43dac3d4b275e92de12ded4d1
        );
        lzybra.grantMintRole(address(lzybraVault));

        console.log("System fully deployed!");

        vm.stopBroadcast();
    }
}
