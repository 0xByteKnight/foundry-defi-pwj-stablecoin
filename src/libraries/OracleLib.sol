// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @author 0xByteKnight
 * @title OracleLib
 * @notice This library is used to check the Chainlink Oracle for stale data. If a price is stale, the function will revert and render the DSCEngine unusable.
 */
library OracleLib {
    /*//////////////////////////////////////////////////////////////
                           State Variables
    //////////////////////////////////////////////////////////////*/

    uint256 private constant TIMEOUT = 3 hours;

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error OracleLib__StalePrice();

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if (secondsSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
