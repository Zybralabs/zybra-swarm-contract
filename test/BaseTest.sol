pragma solidity 0.8.20;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

// core src
import {ERC20} from "../src/token/ERC20.sol";
import {FullDeployment} from "../script/Deployer.s.sol";
import {MockSafe} from "test/mocks/MockSafe.sol";
import "../src/interfaces/IERC20.sol";
import {ZybraVault} from "../src/LZybraSwarmVaultV1.sol";
import {Lzybra} from "../src/token/LZYBRA.sol";
import "../src/AssetTokenData.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AssetTokenFactory} from "../src/AssetTokenFactory.sol";
import {MockPyth} from "../node_modules/@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {PythStructs} from "../node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import {ZybraConfigurator} from "../src/configuration/ZybraConfigurator.sol";

import "../src/DotcManagerV2.sol";
import "../src/DotcV2.sol";
import "test/mocks/MockAdapter.sol";

// mocks
import {mockChainlink} from "../src/mocks/chainLinkMock.sol";

// test env
import "forge-std/Test.sol";

contract BaseTest is FullDeployment, Test {
       address self = address(this);
    address fee = makeAddr("fee");
    address investor = makeAddr("investor");
    address issuer = makeAddr("issuer");
    address guardian = makeAddr("guardian");
    address user = makeAddr("user");
    address nonMember = makeAddr("nonMember");
    address randomUser = makeAddr("randomUser");
    uint128 constant MAX_UINT128 = 50000000 * 10**18;

    // default values
    uint128 public defaultAssetId = 1;
    uint128 public defaultPrice = 5 * 10**18;
    uint128 public amount = 5 * 10**18;
    uint8 public defaultDecimals = 8;

    // Arrays for addresses
    address[] specialAddress = new address[](4);
    address[] authorizationAddresses = new address[](4);
    address[] testAdapters;

    function TestBase() public {
        vm.chainId(1);

        // make yourself owner of the adminSafe
        console.log("----------->");

        // deploy core src
        deploy(address(this));

    

    specialAddress[0] = user;
    specialAddress[1] = investor;
    specialAddress[2] = self;
    specialAddress[3] = randomUser;

    authorizationAddresses[0] = user;
    authorizationAddresses[1] = investor;
    authorizationAddresses[2] = self;
    authorizationAddresses[3] = randomUser;



        // wire src
        // remove deployer access
        // removeDeployerAccess(address(adapter)); // need auth permissions in tests

     



  

      

        uint validTimePeriod = 3600; // Example valid time period
        uint singleUpdateFeeInWei = 0.01 ether; // Example update fee

       
       
        // Label src

        vm.label(address(USDC), "ERC20");
        vm.label(address(lzybravault), "Lzybravault");
        
           // Test creating price feed update data
        bytes32 id = "PriceFeed1"; // Example price feed ID
        int64 price = 2000e6; // Example price
        uint64 conf = 50e7; // Example confidence interval
        int32 expo = 0; // Example exponent
        int64 emaPrice = 1900e6; // Example EMA price
        uint64 emaConf = 40e6; // Example EMA confidence interval
        uint64 publishTime = uint64(block.timestamp);
        uint64 prevPublishTime = publishTime - 1;

        // Create price feed update data
        bytes memory priceFeedData = mockPyth.createPriceFeedUpdateData(
            id,
            price,
            conf,
            expo,
            emaPrice,
            emaConf,
            publishTime,
            prevPublishTime
        );

        // Verify the returned data
        (PythStructs.PriceFeed memory priceFeed, uint64 actualPrevPublishTime) = abi.decode(priceFeedData, (PythStructs.PriceFeed, uint64));
        
        assertEq(priceFeed.id, id);
        assertEq(priceFeed.price.price, price);
        assertEq(actualPrevPublishTime, prevPublishTime);


        // Exclude predeployed src from invariant tests by default
        
       
  
    }

     function setUp() public virtual {
        vm.chainId(1);

        // make yourself owner of the adminSafe
        console.log("----------->");

        // deploy core src
        deploy(address(this));

    

    specialAddress[0] = user;
    specialAddress[1] = investor;
    specialAddress[2] = self;
    specialAddress[3] = randomUser;

    authorizationAddresses[0] = user;
    authorizationAddresses[1] = investor;
    authorizationAddresses[2] = self;
    authorizationAddresses[3] = randomUser;



        // wire src
        // remove deployer access
        // removeDeployerAccess(address(adapter)); // need auth permissions in tests

     



  

      

        uint validTimePeriod = 3600; // Example valid time period
        uint singleUpdateFeeInWei = 0.01 ether; // Example update fee

       
       
        // Label src

        vm.label(address(USDC), "ERC20");
        vm.label(address(lzybravault), "Lzybravault");
        
           // Test creating price feed update data
        bytes32 id = "PriceFeed1"; // Example price feed ID
        int64 price = 2000e6; // Example price
        uint64 conf = 50e7; // Example confidence interval
        int32 expo = 0; // Example exponent
        int64 emaPrice = 1900e6; // Example EMA price
        uint64 emaConf = 40e6; // Example EMA confidence interval
        uint64 publishTime = uint64(block.timestamp);
        uint64 prevPublishTime = publishTime - 1;

        // Create price feed update data
        bytes memory priceFeedData = mockPyth.createPriceFeedUpdateData(
            id,
            price,
            conf,
            expo,
            emaPrice,
            emaConf,
            publishTime,
            prevPublishTime
        );

        // Verify the returned data
        (PythStructs.PriceFeed memory priceFeed, uint64 actualPrevPublishTime) = abi.decode(priceFeedData, (PythStructs.PriceFeed, uint64));
        
        assertEq(priceFeed.id, id);
        assertEq(priceFeed.price.price, price);
        assertEq(actualPrevPublishTime, prevPublishTime);


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
