//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {EnumerableSet} from "lib/openzepplin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {DSCEngine , AggregatorV3Interface} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Test} from "lib/forge-std/src/Test.sol";


contract ContinueOnRevertHandler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint96 public constant MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);


        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    /**
     * function to interact with the dscEngine Contract.
     */

    function mintAndDepositCollateral(uint256 collateralSeed , uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral,0 , MAX_DEPOSIT_AMOUNT);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        collateral.mint(msg.sender , amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
    }


    function redeemCollateral( uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 0 , MAX_DEPOSIT_AMOUNT);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function burnDsc(uint256 amountDsc) public {
        amountDsc = bound(amountDsc, 0 , dsc.balanceOf(msg.sender));
        dsc.burn(amountDsc);
    }

    function mintDsc(uint256 amountDsc) public {
        amountDsc = bound(amountDsc, 0 , MAX_DEPOSIT_AMOUNT);
        dsc.mint(msg.sender , amountDsc);
    }

    function liquidate(uint256 collateralSeed , address userToBeLiquidate, uint256 debtToCover ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        dscEngine.liquidate(address(collateral), userToBeLiquidate , debtToCover);
    }


    /**
     * Function to interact with the DecentralizeStableCoin.
     */

    function transferDsc(uint256 amountDsc, address to) public {
        amountDsc =  bound(amountDsc , 0 , dsc.balanceOf(msg.sender));
        vm.prank(msg.sender);
        dsc.transfer(to , amountDsc);
    }

    /**
     * Function of interact with Aggregator .
     */

    function updateCollateralPrice(uint128, uint256 collateralSeed ) public {
        int256 intNewPrice = 0;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(collateral)));
        priceFeed.updateAnswer(intNewPrice);
    }

    /**
     * Helper Function !
     */

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function callSummary() external view {
        console.log("Weth total deposited", weth.balanceOf(address(dscEngine)));
        console.log("Wbtc total deposited", wbtc.balanceOf(address(dscEngine)));
        console.log("Total supply of DSC", dsc.totalSupply());
    }
}

