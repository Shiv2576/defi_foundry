// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/openzeppelin-contracts/contracts/interfaces/AggregatorV3Interface.sol";



contract DSCEngine is ReentrancyGuard {


    //////////////////////////
    /////// Errors ///////////
    //////////////////////////
    error DSCEngine_NeedMoreThanZero();
    error DSCEngine_TokenAddressesandPriceFeedAddressesMismatch();
    error DSCEngine_TokenNotAllowed();
    error DSCEngine_CollateralTransferFailed();
    error DSCEngine_HealthFactorIsBroken();
    error DSCEngine_MintingFailed();


    //////////////////////////
    /// State Variables //////
    //////////////////////////

    uint256 private constant Additional_Feed_Precesion = 1e10;
    uint256 private constant Precision  = 1e8;
    uint256 private constant Liquidation_Threshold = 50;
    uint256 private constant Liquidation_Precision = 100;
    uint256 private constant Min_Health = 1;



    mapping(address => bool) private s_tokenAllowed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => amountDscMinted) private s_DSCMinted;
    address private s_collateralTokens;




    DecentralizedStableCoin private immutable i_dsc;


    //////////////////////////
    //////  Events      //////
    //////////////////////////


    event CollateralDeposited(address indexed user, address indexed token, uint256  indexed amount);




    ////////////////////
    /// modifiers //////
    ////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine_NeedMoreThanZero();
        }
        _;  
    }

    modifier isAllowedToken(address token) {
        if (s_tokenAllowed[token] == address(0)) {
            revert DSCEngine_TokenNotAllowed();
        }
        _;
    }

    ////////////////////
    //// functions /////    
    ////////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesandPriceFeedAddressesMismatch();
        }

        for (uint256 i=0 ; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }   


    /////////////////////////////
    //// External Functions /////    
    /////////////////////////////

    funtion depositCollatteralAndMintDsc()  external {

    }


   /*
    * @param tokenCollateralAddress address of the Collateral Token
    * @param amountCollateral amount of Collateral to deposit
   */

    function depositCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        ) external 
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonRentrant 
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);


        if (!success) {
            revert  DSCEngine_CollateralTransferFailed();
        }
    }

    function redeemCollateralForDsc() external {

    }

    function redeemCollateral() external {

    }

    function mintDsc() external moreThanZero(amountDscToMint) nonretrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken();
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine_MintingFailed();
        }
    } 
    function burnDsc() external {

    }


    function liquidate() external {

    }

    function getHealthFactor() external view  { 

    }


    ////////////////////////////////////////
    //// Internal & Private  Functions /////    
    ////////////////////////////////////////

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted , uint256 collateralValueInUsd ){
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }


    /*
    * returns how close to liquidation the user is
    * @param if the user get below 1 ,  then they can liquidated.
    */

   function _healthFactor(address user ) private view returns (uint256) {
    // total dsc minted 
    // total collateral value
    (uint256 totalDscMinted , uint256 collateralValueInUsd ) = _getAccountInformation(user);
    uint256 collateralAdjustedForThreshold  =  (collateralValueInUsd * Liquidation_Threshold) / Liquidation_Precision;


    return (collateralAdjustedForThreshold * Precision) / totalDscMinted;

   }


    function _revertIfHealthFactorIsBroken() private view {
        uint256 healthFactor = _healthFactor(user);
        if (userHealthFactor < Min_Health) {
            revert DSCEngine_HealthFactorIsBroken(userHealthFactor);
        }


    }



    ////////////////////////////////////////
    //// public & external view functions /////    
    ////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256) {
        for (uint256 i = 0 ; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += 
        }


    }

    function getUsdValue(address token , uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds(token));
        (,int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * Additional_Feed_Precesion) * amount) / Precision;
    }





}

