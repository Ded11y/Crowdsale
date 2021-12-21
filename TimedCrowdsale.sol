// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Crowdsale.sol";

/**
 * @title TimedCrowdsale
 * @dev Crowdsale accepting contributions only within a time frame.
 */
abstract contract TimedCrowdsale is Crowdsale {
    using SafeMath for uint256;

    uint256 private _openingTime;
    uint256 private _closingTime;

    /**
     * Event for crowdsale extending
     * @param newClosingTime new closing time
     * @param prevClosingTime old closing time
     */
    event CrowdsaleExtended(uint256 prevClosingTime, uint256 newClosingTime);
    event CrowdsalePostponed(uint256 prevOpeningTime, uint256 newOpeningTime);
    event CrowdsaleClosingAdjusted(uint256 prevClosingTime, uint256 newClosingTime);

    /**
     * @dev Reverts if not in crowdsale time range.
     */
    modifier onlyWhileOpen {
        require(isOpen(), "TimedCrowdsale: not open");
        _;
    }

    /**
     * @return the crowdsale opening time.
     */
    function openingTime() public view returns (uint256) {
        return _openingTime;
    }

    /**
     * @return the crowdsale closing time.
     */
    function closingTime() public view returns (uint256) {
        return _closingTime;
    }

    /**
     * @return true if the crowdsale is open, false otherwise.
     */
    function isOpen() public view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp >= _openingTime && block.timestamp <= _closingTime;
    }

    /**
     * @dev Checks whether the period in which the crowdsale is open has already elapsed.
     * @return Whether crowdsale period has elapsed
     */
    function hasClosed() public view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > _closingTime;
    }
    
    function overrideClosingTime(uint256 newClosingTime) external only(CREATOR_ROLE) {
        require(newClosingTime > block.timestamp, "TimedCrowdsale: new closing time is before current time");
        require(newClosingTime > _openingTime, "TimedCrowdsale: closing time is before opening time");
        emit CrowdsaleClosingAdjusted(_closingTime, newClosingTime);
        _closingTime = newClosingTime;
    }
    
    function postponeOpening(uint256 newOpeningTime) external only(CREATOR_ROLE) {
        require(newOpeningTime >= block.timestamp, "TimedCrowdsale: opening time is before current time");
        require(newOpeningTime < _closingTime, "TimedCrowdsale: opening time must be before closing time");
        
        emit CrowdsalePostponed(_openingTime, newOpeningTime);
        _openingTime = newOpeningTime;
    }
    
    function _setPresaleSchedule(uint256 newOpeningTime, uint256 newClosingTime) internal {
        require(newOpeningTime >= block.timestamp, "TimedCrowdsale: opening time is before current time");
        require(newOpeningTime < newClosingTime, "TimedCrowdsale: opening time must be before closing time");
        
        _openingTime = newOpeningTime;
        _closingTime = newClosingTime;
    }
}
