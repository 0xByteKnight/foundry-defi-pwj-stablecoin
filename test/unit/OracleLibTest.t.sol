// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OracleLibTest is Test {
     using OracleLib for AggregatorV3Interface;

      MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;

    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    function testPriceRevertsOnStaleCheck() public {
        // Arrange
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);

        // Act & Assert
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    function testPriceRevertsOnBadAnsweredInRound() public {
        // Arrange
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        
        // Act & Assert
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }
}