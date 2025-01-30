// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "test/mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "test/mocks/MockFailedTransfer.sol";
import {MockFailedMint} from "test/mocks/MockFailedMint.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    MockFailedTransferFrom mockTransferFrom;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address[] public tokenAddresses;
    address[] public priceFeedsAddresses;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");

    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether;
    uint256 public collateralToCover = 20 ether;

    uint256 public constant STARTING_user_BALANCE = 10 ether;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        int256 updatedEthUsdPrice = 15e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(updatedEthUsdPrice);

        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, user, amountToMint);
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_user_BALANCE);
        }

        ERC20Mock(weth).mint(user, STARTING_user_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_user_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           Constructor Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        // Arrange
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);

        // Act & Assert
        new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              Price Tests
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        // Arrange
        uint256 expectedUsd = engine.getUsdValue(weth, amountCollateral);

        // Act
        uint256 actualUsd = engine.getUsdValue(weth, amountCollateral);

        // Assert
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        // Arrange
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        // Act
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        // Assert
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                             Deposit Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfCollateralZero() public {
        // Arrange
        vm.prank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreCollateralThanZero.selector);

        // Act & Assert
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedToken() public {
        // Arrange
        ERC20Mock unapprovedToken = new ERC20Mock();
        ERC20Mock(unapprovedToken).mint(user, STARTING_user_BALANCE);
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedCollateralToken.selector);

        // Act & Assert
        engine.depositCollateral(address(unapprovedToken), STARTING_user_BALANCE);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        // Arrange / Act
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        // Assert
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(amountCollateral, expectedDepositAmount);
    }

    function testDepositWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testRevertIfTransferFromFailed() public {
        // Arrange
        mockTransferFrom = new MockFailedTransferFrom();
        tokenAddresses = [address(mockTransferFrom)];
        priceFeedsAddresses = [ethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedsAddresses, address(mockTransferFrom));

        mockTransferFrom.mint(user, STARTING_user_BALANCE);
        vm.startPrank(user);
        mockTransferFrom.approve(address(mockEngine), STARTING_user_BALANCE);
        vm.stopPrank();

        // Act & Assert
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__DepositCollateralTransferFailed.selector);
        mockEngine.depositCollateral(address(mockTransferFrom), amountCollateral);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              Mint Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfMintZero() public depositedCollateral {
        // Arrange
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreCollateralThanZero.selector);

        // Act & Assert
        engine.mintDsc(0);
    }

    function testRevertIfHealthFactorIsBroken() public depositedCollateral {
        // Arrange
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (amountCollateral * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));

        // Act & Assert
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testMintDscSuccess() public depositedCollateral {
        // Arrange
        vm.prank(user);

        // Act
        engine.mintDsc(amountToMint);

        // Assert
        uint256 totalDscMinted = dsc.balanceOf(user);
        assertEq(totalDscMinted, amountToMint);
    }

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMint mockDsc = new MockFailedMint();
        tokenAddresses = [weth];
        priceFeedsAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedsAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));
        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockEngine), amountCollateral);

        // Act & Assert
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                DepositCollateralAndMintDsc Tests
    //////////////////////////////////////////////////////////////*/

    function testCanDepositCollateralAndMintDsc() public {
        // Arrange
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        // Act
        engine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);

        // Assert
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, amountToMint);
        assertEq(engine.getAccountCollateralValue(user), collateralValueInUsd);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            Burn Dsc Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfBurnZero() public depositedCollateralAndMintedDsc {
        // Arrange
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreCollateralThanZero.selector);
        uint256 amountToBurn = 0;

        // & Act & Assert
        engine.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        // Arrange
        (uint256 totalDscMinted,) = engine.getAccountInformation(user);
        vm.startPrank(user);
        dsc.approve(address(engine), totalDscMinted / 2);

        // Act
        engine.burnDsc(totalDscMinted / 2);

        // Assert
        uint256 leftDscMinted = dsc.balanceOf(user);
        assertEq(leftDscMinted, totalDscMinted / 2);
        vm.stopPrank();
    }

    function testRevertsIfTryToBurnMoreThanUserHas() public {
        // Arrange
        vm.startPrank(user);
        vm.expectRevert();

        // Act & Assert
        engine.burnDsc(amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        RedeemCollateral Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfRedemptionAmountIsZero() public {
        // Arrange
        uint256 amountToRedeem = 0;
        vm.startPrank(user);

        // Act & Assert
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreCollateralThanZero.selector);
        engine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testRevertsIfRedeemingMoreThanDeposited() public {
        // Arrange
        vm.startPrank(user);
        vm.expectRevert();

        // Act & Assert
        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public depositedCollateral {
        // Arrange
        vm.startPrank(user);

        // Act
        engine.redeemCollateral(weth, amountCollateral);

        // Assert
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectParameters() public depositedCollateral {
        // Arrange
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(user, user, weth, amountCollateral);
        vm.startPrank(user);

        // Act & Arrange
        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfTransferFailed() public {
        // Arrange
        MockFailedTransfer mockToken = new MockFailedTransfer();
        tokenAddresses.push(address(mockToken));
        priceFeedsAddresses.push(ethUsdPriceFeed);

        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));

        mockToken.mint(user, amountCollateral);

        vm.startPrank(user);
        mockToken.approve(address(mockEngine), amountCollateral);
        mockEngine.depositCollateral(address(mockToken), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);

        // Act & Arrange
        mockEngine.redeemCollateral(address(mockToken), amountCollateral);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                     RedeemCollateralForDsc Tests
    //////////////////////////////////////////////////////////////*/

    function testRedeemCollateralForDscSuccess() public depositedCollateralAndMintedDsc {
        // Arrange

        vm.startPrank(user);
        dsc.approve(address(engine), amountToMint);

        // Act
        engine.redeemCollateralForDsc(weth, amountCollateral, amountToMint);

        // Assert
        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        // Arrange
        uint256 amountToRedeem = 0;
        vm.startPrank(user);

        // Act & Assert
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreCollateralThanZero.selector);
        engine.redeemCollateralForDsc(weth, amountToRedeem, amountToRedeem);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           Liquidate Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfZeroDebtToCover() public {
        // Arrange
        uint256 debtToCover = 0;

        vm.startPrank(liquidator);

        // Act & Assert
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreCollateralThanZero.selector);
        engine.liquidate(weth, user, debtToCover);

        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsOkay() public depositedCollateralAndMintedDsc {
        // Arrange
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);

        // Act & Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOkay.selector);
        engine.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = engine.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedsAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedsAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockEngine), amountCollateral);
        mockEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockEngine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        mockDsc.approve(address(mockEngine), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockEngine.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          HealthFactor Tests
    //////////////////////////////////////////////////////////////*/

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        // Arrange
        uint256 expectedHealthFactor = 100 ether;

        // Act
        uint256 healthFactor = engine.getHealthFactor(user);

        // Assert
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        // Arrange
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Act
        uint256 userHealthFactor = engine.getHealthFactor(user);

        // Assert
        assert(userHealthFactor == 0.9 ether);
    }
}
