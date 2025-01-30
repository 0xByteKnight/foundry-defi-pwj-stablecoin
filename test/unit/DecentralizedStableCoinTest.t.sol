// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;

    uint256 public constant AMOUNT_TO_MINT = 1 ether;
    uint256 public constant AMOUNT_TO_BURN = 1 ether;
    address public user = makeAddr("user");

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    /*//////////////////////////////////////////////////////////////
                              Mint Tests
    //////////////////////////////////////////////////////////////*/
    function testCannotMintToZeroAddress() public {
        // Arrange
        vm.startPrank(dsc.owner());
        vm.expectRevert();

        // Act & Assert
        dsc.mint(address(0), AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertIfMintZero() public {
        // Arrange
        vm.startPrank(dsc.owner());
        vm.expectRevert();

        // Act & Assert
        dsc.mint(user, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              Burn Tests
    //////////////////////////////////////////////////////////////*/

    function testRevertIfBurnZero() public {
        // Arrange
        vm.startPrank(dsc.owner());
        vm.expectRevert();

        // Act & Assert
        dsc.burn(0);
        vm.stopPrank();
    }

    function testRevertIfBurnMoreThanUserHas() public {
        // Arrange
        vm.startPrank(dsc.owner());
        vm.expectRevert();

        // Act & Assert
        dsc.burn(AMOUNT_TO_BURN);
        vm.stopPrank();
    }
}
