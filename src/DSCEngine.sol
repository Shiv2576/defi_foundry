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
import {ReentrancyGuard} from "lib/openzepplin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzepplin-contracts/contracts/token/ERC20/IERC20.sol";
import {OracleLib, AggregatorV3Interface} from "src/libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    //////////////////////////
    /////// Errors ///////////
    //////////////////////////
    error DSCEngine_NeedMoreThanZero();
    error DSCEngine_TokenAddressesandPriceFeedAddressesMismatch();
    error DSCEngine_TokenNotAllowed(address token);
    error DSCEngine_CollateralTransferFailed();
    error DSCEngine_HealthFactorIsBroken(uint256 healthFactorValue);
    error DSCEngine_MintingFailed();
    error DSCEngine_TransferFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();

    //////////////////////////
    //////// Types ///////////
    //////////////////////////
    using OracleLib for AggregatorV3Interface;

    //////////////////////////
    /// State Variables //////
    //////////////////////////

    uint256 private constant Additional_Feed_Precesion = 1e10;
    uint256 private constant Precision = 1e18;
    uint256 private constant Liquidation_Threshold = 50;
    uint256 private constant Liquidation_Precision = 100;
    uint256 private constant Liquidation_Bonus = 10;
    uint256 private constant Min_Health_Factor = 1e18;
    uint256 private constant Feed_Precesion = 1e8;

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////////////////
    //////  Events      //////
    //////////////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    );

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
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_TokenNotAllowed( token );
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

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////////
    //// External Functions /////
    /////////////////////////////

    /*
     * @param tokenCollateralAddress address of the Collateral Token
     * @param amountCollateral amount of Collateral to deposit
     */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(
        uint256 amount
    ) external moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * collateral : The ERC20 token address of the collateral you are using to make the protocol solvent again.
     * The is collateral that you are going to take from the user who is insolvent.
     * In return , you have to burn your dsc to pay off their debt , but you don't pay off your own.
     * user : The user who is insolvent. They have to have a health_factor < min_health_factor.
     */

    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    )
        external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= Min_Health_Factor) {
            revert DSCEngine_HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            Liquidation_Bonus) / Liquidation_Precision;

        _redeemCollateral(
            collateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );

        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor < Min_Health_Factor) {
            revert DSCEngine_HealthFactorNotImproved();
        }

        revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////
    //// Public Functions ///////
    /////////////////////////////

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_MintingFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of the Collateral Token
     * @param amountCollateral The amount of Collateral to deposit
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    ///////////////////////////////
    //// Private Functions  ///////
    ///////////////////////////////

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine_CollateralTransferFailed();
        }
    }

    function _burnDsc(
        uint256 amountDscToBurn,
        address dscFrom,
        address to
    ) private {
        s_DSCMinted[to] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    ////////////////////////////////////////
    //// Internal & Private  Functions /////
    ////////////////////////////////////////

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * returns how close to liquidation the user is
     * @param if the user get below 1 ,  then they can liquidated.
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total dsc minted
        // total collateral value
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _getUsdValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return
            ((uint256(price) * Additional_Feed_Precesion) * amount) / Precision;
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            Liquidation_Threshold) / Liquidation_Precision;
        return (collateralAdjustedForThreshold * Precision) / totalDscMinted;
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < Min_Health_Factor) {
            revert DSCEngine_HealthFactorIsBroken( healthFactor);
        }
    }

    ////////////////////////////////////////
    //// public & external view functions /////
    ////////////////////////////////////////

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        return ((usdAmountInWei * Precision) /
            (uint256(price) * Additional_Feed_Precesion));
    }

    function getPrecision() external pure returns (uint256) {
        return Precision;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return Additional_Feed_Precesion;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return Liquidation_Threshold;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return Liquidation_Bonus;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return Liquidation_Precision;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return Min_Health_Factor;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
