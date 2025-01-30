// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

/*
 * @title DSCEngine
 * @author 0xByteKnight
 *
 * * The system is designed to be as minimal as possible, and have the tokens maintain a 1 PWJ token == 1 $ peg at all times.
 * * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * This DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the PWJ tokens.
 *
 * @notice This contract is the core of the Decentralized PWJ Stablecoin system. It handles all the logic
 * for minting and redeeming PWJ, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                           State Variables
    //////////////////////////////////////////////////////////////*/
    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS_PERCENTAGE = 10;

    address[] private s_collateralTokens;

    mapping(address token => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;

    /*//////////////////////////////////////////////////////////////
                                Types
    //////////////////////////////////////////////////////////////*/

    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreCollateralThanZero();
    error DSCEngine__NotAllowedCollateralToken();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__DepositCollateralTransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsOkay();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice  This modifier verifies if the amount of deposited tokens is more than zero
     * @param   amount  The amount of tokens deposited
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreCollateralThanZero();
        }
        _;
    }

    /**
     * @notice  This modifier verifies if the deposited token is on a list of allowed tokens to be deposited
     * @param   token  The address of the token that deposited
     */
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedCollateralToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the DSCEngine contract.
     * @dev Sets up the price feed mappings and initializes the DecentralizedStableCoin instance.
     *      Ensures the `tokenAddresses` and `priceFeedAddress` arrays are of the same length.
     * @param tokenAddresses The addresses of allowed collateral tokens.
     * @param priceFeedAddress The addresses of the corresponding price feed contracts.
     * @param dscAddress The address of the DecentralizedStableCoin contract.
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits collateral and mints decentralized stablecoins in a single transaction.
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDscToMint The amount of decentralized stablecoin to mint.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Burns decentralized stablecoins and redeems collateral and  in a single transaction.
     * @param tokenCollateralAddress The address of the token to redeem as collateral.
     * @param amountCollateral The amount of collateral to redeem.
     * @param amountToBurn The amount of decentralized stablecoin to burn.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Partially liquidates a user's collateral to improve their health factor.
     * @dev Requires the user's health factor to be below the `MINIMUM_HEALTH_FACTOR`. The liquidator
     *      burns the specified amount of decentralized stablecoin (`debtToCover`) and receives
     *      the corresponding collateral, including a liquidation bonus.
     * @param tokenCollateralAddress The address of the ERC20 collateral to liquidate from the user.
     * @param user The address of the user with a health factor below the required minimum.
     * @param debtToCover The amount of decentralized stablecoin to burn for the liquidation.
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        nonReentrant
        moreThanZero(debtToCover)
        isAllowedToken(tokenCollateralAddress)
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOkay();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS_PERCENTAGE) / LIQUIDATION_PRECISION;
        _burnDsc(debtToCover, user, msg.sender);
        _redeemCollateral(tokenCollateralAddress, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits collateral into the smart contract.
     * @dev Verifies the collateral token is allowed and the amount is greater than zero.
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__DepositCollateralTransferFailed();
        }
    }

    /**
     * @notice Mints decentralized stablecoins.
     * @dev Ensures the amount is greater than zero and the user's health factor is above the minimum threshold.
     * @param amountDscToMint The amount of decentralized stablecoin to mint.
     */
    function mintDsc(uint256 amountDscToMint) public nonReentrant moreThanZero(amountDscToMint) {
        s_dscMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice Burns decentralized stablecoins from the user's balance.
     * @dev Verifies the amount is greater than zero, reverts if the user's health factor is below the minimum threshold.
     * @param amountToBurn The amount of decentralized stablecoin to burn.
     */
    function burnDsc(uint256 amountToBurn) public moreThanZero(amountToBurn) {
        _burnDsc(amountToBurn, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Redeems collateral from the system.
     * @dev Verifies the collateral amount is greater than zero, reverts if the user's health factor is below the minimum threshold.
     * @param tokenCollateralAddress The address of the token to redeem as collateral.
     * @param amountCollateral The amount of collateral to redeem.
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Calculates the total value of a user's collateral in USD.
     * @param user The address of the user whose collateral value is being calculated.
     * @return totalCollateralValueInUsd The total collateral value in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Converts a token amount to its USD value using the token's price feed.
     * @param token The address of the token to evaluate.
     * @param amount The amount of the token.
     * @return The USD value of the specified token amount.
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    /**
     * @notice Converts a USD amount (in Wei) to the equivalent amount of a specified token.
     * @dev Uses the token's price feed to determine the conversion rate.
     * @param tokenCollateralAddress The address of the token whose amount is to be calculated.
     * @param usdAmountInWei The USD amount (in Wei) to be converted to the token amount.
     * @return The equivalent amount of the token for the specified USD amount.
     */
    function getTokenAmountFromUsd(address tokenCollateralAddress, uint256 usdAmountInWei)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /*//////////////////////////////////////////////////////////////
                          Internal Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks the user's health factor and reverts if it meets or exceeds the minimum threshold.
     * @dev Ensures the user's health factor is below `MINIMUM_HEALTH_FACTOR` to indicate a liquidation condition.
     * @param user The address of the user whose health factor is being checked.
     */
    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          Private Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Burns a specified amount of decentralized stablecoin (DSC) on behalf of a user.
     * @dev Transfers the DSC from the specified address, decreases the user's minted DSC record, and burns the DSC.
     * @param amountToBurn The amount of DSC to burn.
     * @param onBehalfOf The address of the user whose minted DSC record will be reduced.
     * @param dscFrom The address from which the DSC will be transferred for burning.
     */
    function _burnDsc(uint256 amountToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToBurn);
    }

    /**
     * @notice Redeems collateral from the system and transfers it to the specified address.
     * @dev Updates the collateral record and emits a `CollateralRedeemed` event. Ensures the transfer is successful.
     * @param tokenCollateralAddress The address of the ERC20 token being redeemed.
     * @param amountCollateral The amount of collateral to redeem.
     * @param from The address from which the collateral is being redeemed.
     * @param to The address to which the collateral will be transferred.
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Calculates the user's health factor.
     * @dev If the health factor drops below 1, the user can be liquidated.
     * @param user The address of the user.
     * @return The health factor of the user.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice Calculates the health factor of a user based on their total minted DSC and collateral value.
     * @dev The health factor determines whether a user is at risk of liquidation.
     *      If the health factor falls below 1, the user can be liquidated.
     * @param totalDscMinted The total amount of decentralized stablecoin minted by the user.
     * @param collateralValueInUsd The total value of the user's collateral in USD.
     * @return The calculated health factor.
     */
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice Retrieves account information for a user.
     * @param user The address of the user.
     * @return totalDscMinted The total amount of decentralized stablecoin minted by the user.
     * @return collateralValueInUsd The total value of the user's collateral in USD.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Retrieves the USD value of a given amount of a specific token using Chainlink price feeds.
     * @dev Fetches the latest price from the token's associated price feed and calculates the USD value.
     * @param token The address of the token to evaluate.
     * @param amount The amount of the token to convert to USD.
     * @return The USD value of the specified token amount.
     */
    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
              External and Public View & Pure Functions
    //////////////////////////////////////////////////////////////*/
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS_PERCENTAGE;
    }

    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getMinimumHealthFactor() public pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
