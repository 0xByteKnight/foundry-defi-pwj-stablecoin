// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));

        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}
