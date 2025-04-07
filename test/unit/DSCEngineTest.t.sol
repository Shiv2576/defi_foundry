// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { MockMoreDebtDSC } from "../mocks/MockMoreDebtDSC.sol";
import { MockFailedMintDSC } from "../mocks/MockFailedMintDSC.sol";
import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo , address token , uint256 amount);


    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;


    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    uint256 public constant Starting_User_Balance = 10 ether;
    uint256 public constant Min_Health_Factor = 1e18;
    uint256 public constant Liquidation_Threshold = 50;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;


    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce , helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc , ) = helperConfig.activeNetworkConfig();

        if (block.chainid == 31_337) {
            vm.deal(user , Starting_User_Balance);
        }

        ERC20Mock(weth).mint(user , Starting_User_Balance);
        ERC20Mock(wbtc).mint(user, Starting_User_Balance);
    }

    ///////////////////////////
    //// Constructor Test /////
    ///////////////////////////

    address[] public tokenAddresses;
    address[] public feedAddresses;


    // function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
    //     tokenAddresses.push(weth);
    //     feedAddresses.push(ethUsdPriceFeed);
    //     feedAddresses.push(btcUsdPriceFeed);

    //     vm.expectRevert(DSCEngine.DSCEngine_TokenLengthDoesntMatchPriceFeed.selector);
    //     new DSCEngine(tokenAddresses,feedAddresses, address(dsc));
    // }

    ////////////////////
    ////Price tests/////
    ////////////////////

    function testGetTokenAmountFromUsd() public {
        uint256 expectedWeth =  0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(expectedWeth, amountWeth);
    }

    function testGetUsdValue() public  {
        uint256 ethAmount = 15e18;
        uint256 expectedValue = 30_000e18;
        uint256 usdValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(usdValue , expectedValue); 
    }


    ///////////////////////////////////
    ////// depositCollateral Test /////
    ///////////////////////////////////

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockCollateralToken = new MockFailedTransferFrom();
        tokenAddresses = [address(mockCollateralToken)];
        feedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
        mockCollateralToken.mint(user, amountCollateral);
        vm.startPrank(user);
        ERC20Mock(address(mockCollateralToken)).approve(address(mockDsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        mockDsce.depositCollateral(address(mockCollateralToken), amountCollateral);
        vm.stopPrank();
    }


    function testrevertIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine_NeedMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }




    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN" , user , 100e18);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_TokenNotAllowed.selector, address(randToken)));
        dsce.depositCollateral(address(randToken), amountCollateral);
        vm.stopPrank();
    }


    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth , amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithOutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, amountCollateral);
    }


    /////////////////////////////////////////////
    ////// depositCollateralAndMintDsc Test /////
    /////////////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_HealthFactorIsBroken.selector, expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }














}
