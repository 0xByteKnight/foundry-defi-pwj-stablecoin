// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFailedTransfer is ERC20 {
    constructor() ERC20("Decentralized PWJ StableCoin", "PWJ") {}

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
