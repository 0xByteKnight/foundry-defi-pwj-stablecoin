// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author 0xByteKnight
 * Collateral: Exogenous (ETH & BTC)
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * @notice This contract is meant to be governed by DSCEngine. It is an ERC20 token that can be minted and burned by the DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the DecentralizedStableCoin contract.
     * @dev Sets the token name as "Decentralized PWJ StableCoin" and the symbol as "PWJ".
     *      Assigns the contract deployer as the owner using the Ownable constructor.
     */
    constructor() ERC20("Decentralized PWJ StableCoin", "PWJ") Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints new tokens to the specified address.
     * @dev Only the contract owner can call this function. Ensures the `_to` address is non-zero
     *      and the `_amount` is greater than zero before minting.
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @return Returns `true` upon successful execution.
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount == 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Burns a specified amount of tokens from the caller's balance.
     * @dev Only the contract owner can call this function. Ensures the `_amount` is greater than zero
     *      and does not exceed the caller's current balance.
     * @param _amount The amount of tokens to burn.
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount == 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }
}
