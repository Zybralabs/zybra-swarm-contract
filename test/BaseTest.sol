pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

// core src
import {ERC20} from "../src/token/ERC20.sol";
import {Deployer} from "../../script/Deployer.s.sol";
import {MockSafe} from "test/mocks/MockSafe.sol";
import "../src/interfaces/IERC20.sol";
import {LzybraVault} from "../src/LZybraSwarmVaultV1.sol";
import {Lzybra} from "../src/token/LZYBRA.sol";
import "../src/AssetTokenData.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {AssetTokenFactory} from "../src/AssetTokenFactory.sol";

import "../src/DotcManagerV2.sol";
import "../src/DotcV2.sol";
import "test/mocks/MockAdapter.sol";

import {MessagesLib} from "../../../src/libraries/MessagesLib.sol";
// mocks
import {mockChainlink} from "../src/mocks/chainLinkMock.sol";
import {MockGasService} from "../../test/mocks/MockGasService.sol";

// test env
import "forge-std/Test.sol";

contract BaseTest is Deployer, Test {
    DotcV2 dotcV2;
    DotcManagerV2 dotcManagerV2;
    MockAdapter adapter1;
    MockAdapter adapter2;
    mockChainlink public ChainLinkMockUSDC;
    mockChainlink public ChainLinkMockNVIDIA;
    mockChainlink public ChainLinkMockMSCRF;
    AssetTokenData assetTokenData;
    AssetToken public asset1;
    AssetToken public asset2;
    AssetToken public asset3;
    AssetTokenFactory assetTokenFactory;
    MockAdapter adapter3;
    address[] testAdapters;
    ERC20 public USDC;
    
    LzybraVault public lzybravault;
    Lzybra public lzybra;
    address self = address(this);
    address fee = makeAddr("fee");
    address investor = makeAddr("investor");
    address issuer = makeAddr("issuer");
    address guardian = makeAddr("guardian");
    address user = makeAddr("user");
    address nonMember = makeAddr("nonMember");
    address randomUser = makeAddr("randomUser");
    uint128 constant MAX_UINT128 = type(uint128).max;
    uint256 constant GATEWAY_INITIAL_BALACE = 10 ether;

    // default values
    uint128 public defaultAssetId = 1;
    uint128 public defaultPrice = 5 * 10**18;
    uint8 public defaultDecimals = 8;

    function setUp() public virtual {
        vm.chainId(1);

        // make yourself owner of the adminSafe
        address[] memory pausers = new address[](1);
        pausers[0] = self;
        adminSafe = address(new MockSafe(pausers, 1));

        // deploy core src
        deploy(address(this));

        // deploy mock adapters

        adapter1 = new MockAdapter(address(gateway));
        adapter2 = new MockAdapter(address(gateway));
        adapter3 = new MockAdapter(address(gateway));

        adapter1.setReturn("estimate", uint256(1 gwei));
        adapter2.setReturn("estimate", uint256(1.25 gwei));
        adapter3.setReturn("estimate", uint256(1.75 gwei));

        testAdapters.push(address(adapter1));
        testAdapters.push(address(adapter2));
        testAdapters.push(address(adapter3));

        // wire src
        wire(address(adapter1));
        // remove deployer access
        // removeDeployerAccess(address(adapter)); // need auth permissions in tests

        USDC = _newErc20("X's Dollar", "USDX", 6);
        assetTokenData = new AssetTokenData(0);
        assetTokenFactory = new AssetTokenFactory();
        assetTokenFactory.initialize(address(assetTokenData));
        asset1 = AssetToken(assetTokenFactory.deployAssetToken(issuer, guardian, 500000000000000000,"ipfs://tbd",1000000000000000000,"NVIDIA","NVIDIA"));
        asset2 = AssetToken(assetTokenFactory.deployAssetToken(issuer, guardian, 500000000000000000,"ipfs://tbd",1000000000000000000,"MCSF","MCSF"));
        asset3 = AssetToken(assetTokenFactory.deployAssetToken(issuer, guardian, 500000000000000000,"ipfs://tbd",1000000000000000000,"TESLA","TESLA"));
        lzybra = new Lzybra("Lzybra", "LZYB");





        ChainLinkMockUSDC = new mockChainlink();
        ChainLinkMockNVIDIA = new mockChainlink();
        ChainLinkMockMSCRF = new mockChainlink();

        ChainLinkMockUSDC.setPrice(1e18);
        ChainLinkMockNVIDIA.setPrice(8e18);
        ChainLinkMockMSCRF.setPrice(10e18);

        dotcManagerV2 = new DotcManagerV2();
        dotcManagerV2.initialize(fee);
        dotcV2 = new DotcV2();
        dotcV2.initialize(dotcManagerV2);

        // configurator.initGTialize(address(this), USDC);
        lzybravault = new LzybraVault(address(lzybra),address(dotcV2),address(USDC), address(self));
        lzybra.grantMintRole(address(lzybravault));
        gateway.file("adapters", testAdapters);
        vm.deal(address(gateway), GATEWAY_INITIAL_BALACE);

       
        // Label src

        vm.label(address(USDC), "ERC20");
        vm.label(address(lzybravault), "Lzybravault");
        

        // Exclude predeployed src from invariant tests by default
        
       
  
    }
   
    function testSetup()public virtual{
    
        setUp();
    }
   
    // helpers




 

    // function deposit(address _vault, address _investor, uint256 amount,uint256 lzybra_amount) public {
    //     deposit(_vault, _investor, amount, true,lzybra_amount);
    // }

    // function deposit(address _vault, address _investor, uint256 amount, bool claimDeposit, uint256 lzybra_amount) public {
    //     erc20.mint(_investor, amount);
    //         // member
    //     vm.startPrank(_investor);
    //     Lzybravault.setEndorsedOperator(address(this), true, address(vault));
    //     erc20.approve(address(Lzybravault), amount); // add allowance
    //     console.log("withdraw====>");
    //     Lzybravault.requestDeposit(amount, _vault);
    //     // trigger executed collectInvest
    //     uint128 assetId = poolManager.assetToId(USDC); // retrieve assetId
    
    //      uint256 shares = vault.maxMint(_investor);
    //     if (claimDeposit) {
    //         uint256 numerator = 75;
    //     uint256 denominator = 100;
    //     uint256 multiplier = numerator * 1e18 / denominator; // Using a large number to avoid fractional division

    //         Lzybravault.deposit(amount, address(vault), lzybra_amount); // claim the tranches
    //     }
    //     vm.stopPrank();
    // }

    // Helpers
    function _addressToBytes32(address x) internal pure returns (bytes32) {
        return bytes32(bytes20(x));
    }

    function _newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 asset = new ERC20(decimals);
        asset.file("name", name);
        asset.file("symbol", symbol);
        return asset;
    }

    function _bytes16ToString(bytes16 _bytes16) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 16 && _bytes16[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 16 && _bytes16[i] != 0; i++) {
            bytesArray[i] = _bytes16[i];
        }
        return string(bytesArray);
    }

    function _uint256ToString(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function random(uint256 maxValue, uint256 nonce) internal view returns (uint256) {
        if (maxValue == 1) {
            return maxValue;
        }
        uint256 randomnumber = uint256(keccak256(abi.encodePacked(block.timestamp, self, nonce))) % (maxValue - 1);
        return randomnumber + 1;
    }

    // assumptions
    function amountAssumption(uint256 amount) public pure returns (bool) {
        return (amount > 1 && amount < MAX_UINT128);
    }

    function addressAssumption(address user) public view returns (bool) {
        return (user != address(0) && user != address(USDC) && user.code.length == 0);
    }
}
