// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedMint is ERC20Burnable, Ownable {
    constructor() ERC20("Decentralized PWJ StableCoin", "PWJ") Ownable(msg.sender) {}

    function mint(address, /*_to*/ uint256 /*_amount*/ ) external pure returns (bool) {
        return false;
    }
}
