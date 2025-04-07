//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { AggregatorV3Interface } from "lib/chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";

/**
 * @title Oracle Library
 * @notice This library is used to check the chainlink oracle for stale data.
 * if a price is stale , functions will revert , and render the DSCEngine unusable - this is by design.
 * We want DSCEngine to freeze if the prices become stale.
 */

library OracleLib {

    error OracleLib_StalePrice();

    uint256 private constant timeout = 3 hours;


    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed) public view returns (uint80, int256 , uint256 , uint256 , uint80) {
        (uint80 roundId, int256 answer ,uint256  startedAt , uint256 updatedAt , uint80 answeredInRound) = chainlinkFeed.latestRoundData();


        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib_StalePrice();
        }

        uint256 secondSince = block.timestamp - updatedAt;
        if (secondSince > timeout) {
            revert OracleLib_StalePrice();
        }

        return (roundId, answer , startedAt , updatedAt , answeredInRound);

    }

    function getTimeout(AggregatorV3Interface) public pure returns (uint256) {
        return timeout;
    }
}