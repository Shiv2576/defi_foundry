// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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
// view & pure functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {ERC20Burnable , ERC20 } from "lib/openzepplin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import { Ownable} from "lib/openzepplin-contracts/contracts/access/Ownable.sol";

/*
  * @title Decentralized Stable Coin
  * Collateral : Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized
  * Stability : Low Volatility
  * Minting : Algorithmic
  * This is ERC20 token with minting and burning capabilities.
*/



contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin_AmountMustbeMoreThanZero();
    error DecentralizedStableCoin_BurnAmountExceedsBalance();
    error DecentralizedStableCoin_NotZeroAddress();


    constructor() ERC20("DecentralizedStableCoin" , "DSC" ) {}

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);

        if (_amount == 0) {
            revert DecentralizedStableCoin_AmountMustbeMoreThanZero();
        }

        if (balance <= _amount) {
            revert DecentralizedStableCoin_BurnAmountExceedsBalance();
        }

        super.burn(_amount);
 
    }


    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if ( _to == address(0)) {
            revert DecentralizedStableCoin_NotZeroAddress();    
        }

        if (_amount <- 0) {
            revert DecentralizedStableCoin_AmountMustbeMoreThanZero();
            
        }

        _mint(_to, _amount);
        return true;
    }








}
