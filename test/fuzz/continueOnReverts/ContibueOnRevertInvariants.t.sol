//SPDX-License-Indentifier: MIT


pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../../script/DeployDSC.s.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { ContinueOnRevertHandler } from "./ContinueOnRevertHandler.t.sol";
import { console } from "forge-std/console.sol";

contract ContinueOnRevertsInvariants is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;


    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    ContinueOnRevertHandler public handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed , btcUsdPriceFeed, weth ,  wbtc , ) = helperConfig.activeNetworkConfig();
        handler = new ContinueOnRevertHandler(dsce, dsc);
        targetContract(address(dsce));
    }

    function invarient_protocolMustHaveMoreValueThanTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));
       

        uint256 wethvalue = dsce.getUsdValue(weth, wethDeposited);
        uint256 wbtcvalue = dsce.getUsdValue(wbtc , wbtcDeposited);



        console.log("wethValue: &s", wethvalue);
        console.log("wbtcValue: &s", wbtcvalue);

        assert(wethvalue + wbtcvalue >= totalSupply);
    }

    function invarient_callSummary()  public view {
        handler.callSummary();
    }
}

