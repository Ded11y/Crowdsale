// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControlMixin} from "./AccessControlMixin.sol";

/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conforms
 * the base architecture for crowdsales.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropriate to concatenate behavior.
 */
contract Crowdsale is Context, AccessControlMixin, ReentrancyGuard {
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The token being sold
    IERC20 internal _token;

    // Address where funds are collected
    address payable internal _wallet;

    // Address holding the tokens, which has approved allowance to the crowdsale.
    address internal _tokenWallet;
    
    // How many token units a buyer gets per wei.
    // The rate is the conversion between wei and the smallest and indivisible token unit.
    // So, if you are using a rate of 1 with a ERC20Detailed token with 3 decimals called TOK
    // 1 wei will give you 1 unit, or 0.001 TOK.
    uint256 internal _rate;

    // Amount of wei raised
    uint256 internal _weiRaised;

    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event SetRate(address sender, uint256 rate);
    event SetWallet(address sender, address payable wallet);
    event SetToken(address sender, IERC20 token);
    event SetTokenWallet(address sender, address wallet);

    /**
     * @return the token being sold.
     */
    function getToken() public view returns (IERC20) {
        return _token;
    }

    /**
     * @return the address where funds are collected.
     */
    function getWallet() public view returns (address payable) {
        return _wallet;
    }
    
    function getTokenWallet() public view returns(address) {
        return _tokenWallet;
    }

    /**
     * @return the number of token units a buyer gets per wei.
     */
    function getRate() public view returns (uint256) {
        return _rate;
    }

    /**
     * @return the amount of wei raised.
     */
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(uint256 weiAmount) virtual internal view returns (uint256) {
        return weiAmount.mul(_rate);
    }
    
    /**
     * @dev Checks the amount of tokens left in the allowance.
     * @return Amount of tokens left in the allowance
     */
    function remainingTokens() public view returns (uint256) {
        return Math.min(_token.balanceOf(_tokenWallet), _token.allowance(_tokenWallet, address(this)));
    }

    function setNewRate(uint256 rate) external only(CREATOR_ROLE) {
        _rate = rate;
        emit SetRate(_msgSender(), rate);
    }
    
    function setNewWallet(address payable wallet) external only(CREATOR_ROLE) {
        _wallet = wallet;
        emit SetWallet(_msgSender(), wallet);
    }
    
    function setNewToken(IERC20 token) external only(CREATOR_ROLE) {
        _token = token;
        emit SetToken(_msgSender(), token);
    }
    
    function setTokenWallet(address wallet) external only(CREATOR_ROLE) {
        _tokenWallet = wallet;
        emit SetTokenWallet(_msgSender(), wallet);
    }

}
