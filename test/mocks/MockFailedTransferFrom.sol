// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFailedTransferFrom is ERC20 {
    constructor() ERC20("Decentralized PWJ StableCoin", "PWJ") {}

    function transferFrom(address, /*sender*/ address, /*recipient*/ uint256 /*amount*/ )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
