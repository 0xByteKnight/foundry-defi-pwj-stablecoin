// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    address[] public usersWithDepositedCollateral;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    /*//////////////////////////////////////////////////////////////
                              DSCEngine
    //////////////////////////////////////////////////////////////*/
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithDepositedCollateral.push(msg.sender);
    }

    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if (usersWithDepositedCollateral.length == 0) {
            return;
        }
        address sender = usersWithDepositedCollateral[addressSeed % usersWithDepositedCollateral.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = int256(collateralValueInUsd / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }

        amountToMint = bound(amountToMint, 0, uint256(maxDscToMint));
        if (amountToMint == 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function burnDsc(uint256 amountDsc) public {
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        if (amountDsc == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dsc.approve(address(engine), amountDsc);
        engine.burnDsc(amountDsc);
        vm.stopPrank();
    }

    // function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));

    //     amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
    //     if (amountCollateral == 0) {
    //         return;
    //     }

    //     vm.startPrank(msg.sender);
    //     engine.redeemCollateral(address(collateral), amountCollateral);
    //     vm.stopPrank();
    // }

    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        uint256 minHealthFactor = engine.getMinimumHealthFactor();
        uint256 userHealthFactor = engine.getHealthFactor(userToBeLiquidated);
        if (userHealthFactor >= minHealthFactor) {
            return;
        }

        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        engine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /*//////////////////////////////////////////////////////////////
                       DecentralizedStableCoin
    //////////////////////////////////////////////////////////////*/

    function transferDsc(uint256 amountDsc, address to) public {
        if (to == address(0)) {
            to = address(1);
        }
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        vm.prank(msg.sender);
        dsc.transfer(to, amountDsc);
    }

    /*//////////////////////////////////////////////////////////////
                              Aggregator
    //////////////////////////////////////////////////////////////*/

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    /*//////////////////////////////////////////////////////////////
                           Helper Functions
    //////////////////////////////////////////////////////////////*/
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
