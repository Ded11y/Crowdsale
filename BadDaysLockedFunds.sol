// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "./MaticWETH.sol";
import "./Crowdsale.sol";
import "./CappedCrowdsale.sol";
import "./TimedCrowdsale.sol";
import {AccessControlMixin} from "./AccessControlMixin.sol";
import {ContextMixin} from "./ContextMixin.sol";
import {NativeMetaTransaction} from "./NativeMetaTransaction.sol";

contract BadDaysLockedFunds is Pausable, CappedCrowdsale, TimedCrowdsale, ContextMixin, NativeMetaTransaction {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    string public name = "BadDaysLockedFunds";
    
    //Whitelisted addresses that can engage in pre-sale 
    mapping(address => bool) internal whitelisted;
    
    //Constant counter for a month = 30 days = 2,592,000 seconds
    uint256 public oneMonth;
    
    //Acocunt -> Category -> Month -> Amount
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public claimedTokensForTheMonth;
    
    //Override control to enable withdrawal after TGE has been defined and the pre-sale has been closed
    bool internal canWithdraw;
    
    //Override date for the TGE - needs to be manually set
    uint256 public dayOfTGE;
    
    //MNFT token address
    //IERC20 internal _maticWeth;
    
    /*
    Categories
    Index from 0 - 12
    0 - Team
    1 - Operations
    2 - Marketing
    3 - Advisors
    4 - Growth Fund
    5 - Escrow Vault
    6 - Play Rewards
    7 - Seed Round
    8 - Strategic Round
    9 - Private Round 1
    10 - Private Round 2
    11 - Public Round
    */
    uint256 public activeCatIndex;
    
    //Holder of category with index
    mapping(uint256 => Category) public fundCategory;
    
    //variable to hold the funds for category 0 - 6
    mapping(address => mapping(uint256 => uint256)) public lockedFundForCategoryFor;
    
    //Balance for a specific wallet of a specific category (0 - 6)
    mapping(address => mapping(uint256 => uint256)) public balanceOfLockedFundForCategoryFor;
    
    //Holder of the address of the holder of the allocated fund per category (0 - 6)
    mapping(uint256 => address) public accountForCategory;
    
    //total balance of the main vault from start to end, across all categories
    uint256 public vaultBalance;
    
    //Struct that defines the configurations of each Category
    struct Category {
        string desc;
        uint256 index;
        uint256 lockPeriod;
        uint256 periodAfterTGE;
        uint256 percentClaimableAfterTGE;
        uint256 percentClaimablePerMonth;
    }
    
    event SetPresaleSchedule(address sender, uint256 openingTime, uint256 closingTime, uint256 cap, uint256 rate, uint256 index);
    event WithdrawTokens(address sender, address beneficiary, uint256 amount);
    event UpdateWhitelist(address sender, address[] accounts, bool mode);
    event ConfigCategory(string desc, uint256 index, uint256 lockPeriod, uint256 periodAfterTGE, uint256 percentClaimableAfterTGE, uint256 percentClaimablePerMonth);
    event LockAllocation(uint256 index, address account, uint256 amount, address sender);
    event SetTGE(address sender, uint256 value);
    event CanWithdraw(address sender, bool canWithdraw);
    event SendFundsAfterTGE(address account, uint256 category, uint256 claimable);
    
    constructor(
        IERC20 token,            // the token
        address tokenwallet     // tokenWallet of the token
    )
        public
    {
        _setupContractId(name);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(CREATOR_ROLE, _msgSender());
        //_wallet = wallet;
        _tokenWallet = tokenwallet;
        _token = token;
        //_maticWeth = maticWeth;
        
        //For Production Live
        /*
        _configCategory("Team", 0, 15552000, 0, 0, 500);
        _configCategory("Operations", 1, 7776000, 0, 0, 500);
        _configCategory("Marketing", 2, 7776000, 0, 0, 500);
        _configCategory("Advisors", 3, 2592000, 0, 0, 1000);
        _configCategory("Growth Fund", 4, 15552000, 0, 0, 500);
        _configCategory("Escrow Vault", 5, 2592000, 0, 0, 10000);
        _configCategory("Play Rewards", 6, 2592000, 0, 0, 500);
        _configCategory("Seed Round", 7, 2592000, 2592000, 1000, 1125);
        _configCategory("Strategic Round", 8, 0, 2419200, 500, 1187);
        _configCategory("Private Round 1", 9, 0, 1814400, 700, 1550);
        _configCategory("Private Round 2", 10, 0, 1209600, 1300, 1740);
        _configCategory("Public Round", 11, 0, 604800, 2000, 4000);
        
        oneMonth = 2592000;
        */
 
        _configCategory("Team", 0, 1080, 0, 0, 500);
        _configCategory("Operations", 1, 540, 0, 0, 500);
        _configCategory("Marketing", 2, 540, 0, 0, 500);
        _configCategory("Advisors", 3, 180, 0, 0, 1000);
        _configCategory("Growth Fund", 4, 1080, 0, 0, 500);
        _configCategory("Escrow Vault", 5, 180, 0, 0, 10000);
        _configCategory("Play Rewards", 6, 180, 0, 0, 500);
        _configCategory("Seed Round", 7, 180, 180, 1000, 1125);
        _configCategory("Strategic Round", 8, 0, 168, 500, 1187);
        _configCategory("Private Round 1", 9, 0, 126, 700, 1550);
        _configCategory("Private Round 2", 10, 0, 84, 1300, 1740);
        _configCategory("Public Round", 11, 0, 42, 2000, 4000);
        oneMonth = 180;
        
        _initializeEIP712(name);
    }
    
    function pause() external only(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external only(PAUSER_ROLE) {
        _unpause();
    }

    function _msgSender() internal override view returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }
    
    //function isApprovedToSpend(address account) external view returns (uint256) {
    //    return _maticWeth.allowance(account, address(this));
    //}
    
    function setTGE(uint256 value) external only(CREATOR_ROLE) {
        dayOfTGE = value;
        emit SetTGE(_msgSender(), value);
    } 
    
    /// @notice This fuction configures aech category for the token sale
    /// @param desc - name of the category
    /// @param index - base 0 index of the category
    /// @param lockPeriod - lock period in seconds
    /// @param periodAfterTGE - lock period after TGE in seconds
    /// @param percentClaimableAfterTGE - percent for initial withdrawal after TGE. Note. Actual percent * 100
    /// @param percentClaimablePerMonth - monthly withdrawal percentage. Note. Actual percent * 100
    function _configCategory(string memory desc, uint256 index, uint256 lockPeriod, uint256 periodAfterTGE, uint256 percentClaimableAfterTGE, uint256 percentClaimablePerMonth) internal {
        fundCategory[index] = Category(
            desc,
            index,
            lockPeriod,
            periodAfterTGE,
            percentClaimableAfterTGE,
            percentClaimablePerMonth
        );
    }
    
    function configCategory(string memory desc, uint256 index, uint256 lockPeriod, uint256 periodAfterTGE, uint256 percentClaimableAfterTGE, uint256 percentClaimablePerMonth) 
    external only(CREATOR_ROLE) {
        _configCategory(desc, index, lockPeriod, periodAfterTGE, percentClaimableAfterTGE, percentClaimablePerMonth);
        emit ConfigCategory(desc, index, lockPeriod, periodAfterTGE, percentClaimableAfterTGE, percentClaimablePerMonth);
    }
    
    function getCategoryConfig(uint256 code) external view
    returns (string memory desc, uint256 index, uint256 lockPeriod, uint256 periodAfterTGE, uint256 percentClaimableAfterTGE, uint256 percentClaimablePerMonth) {
        Category storage category = fundCategory[code];
        return(category.desc, category.index, category.lockPeriod, category.periodAfterTGE, category.percentClaimableAfterTGE, category.percentClaimablePerMonth);
    }
    
    
    /**
     * @notice This locks a specific fund for a specified wallet. Funds can be withdrawn on a monthly
     * basis depending on the configuration.
     * @param index - Category index for the locked funds
     * @param account - Wallet address to be assigned to the locked funds. Monthly claimable amount will
     * be sent to this address.
     * @param amount - Amount in token bits to be locked for the specific account and category
     */
    function lockAllocation(uint256 index, address account, uint256 amount) external only(CREATOR_ROLE) {
        require(index <= 6, "BadDaysCrowdsale: Invalid category");
        require(account != address(0), "BadDaysCrowdsale: recipient cannot be address 0");

        address holder = accountForCategory[index];

        if(holder != address(0)) {
            require(holder == account, "Category already assigned to address");
        }
        
        lockedFundForCategoryFor[account][index] = lockedFundForCategoryFor[account][index].add(amount);
        balanceOfLockedFundForCategoryFor[account][index] = balanceOfLockedFundForCategoryFor[account][index].add(amount);
        accountForCategory[index] = account;
        vaultBalance = vaultBalance.add(amount);
        _token.safeTransferFrom(_tokenWallet, address(this), amount);
        
        emit LockAllocation(index, account, amount, _msgSender());
    }
    
    function getClaimableLockedFunds(address account, uint256 index) external view returns(uint256) {
        require(dayOfTGE > 0, "BadDaysCrowdsale: No TGE yet");
        require(index <= 6, "BadDaysCrowdsale: Invalid category");
        require(lockedFundForCategoryFor[account][index] > 0, "BadDaysCrowdsale: No fund for this account");
        require(balanceOfLockedFundForCategoryFor[account][index] > 0, "BadDaysCrowdsale: Zero balance for this account");
        
        Category storage category = fundCategory[index];
        require(block.timestamp > dayOfTGE.add(category.lockPeriod.mul(1 seconds)), "BadDaysCrowdsale: Funds still locked");
        
        uint256 distMonth = getDistributionMonth();
        uint256 lockedMonths = (category.lockPeriod.mul(1 seconds).div(oneMonth)).add(1); 
 
        uint256 claimable;
        if(block.timestamp > dayOfTGE.add(category.lockPeriod.mul(1 seconds))) {
            if(claimedTokensForTheMonth[account][index][distMonth] == 0) {
                for (uint256 i = lockedMonths; i <= distMonth; i++) {
                    if(claimedTokensForTheMonth[account][index][i] == 0) {
                        claimable = claimable.add((lockedFundForCategoryFor[account][index].mul(category.percentClaimablePerMonth)).div(10000));
                        if (claimable >= balanceOfLockedFundForCategoryFor[account][index]) break;
                    }
                }
            }   
            if (claimable > 0) {
                if (claimable > balanceOfLockedFundForCategoryFor[account][index])
                    claimable = balanceOfLockedFundForCategoryFor[account][index];
            }
        }
        return claimable;
    }
    
    function withdrawLockedFunds(address account, uint256 index) external whenNotPaused only(CREATOR_ROLE) {
        require(dayOfTGE > 0, "BadDaysCrowdsale: No TGE yet");
        require(index <= 6, "BadDaysCrowdsale: Invalid category");
        require(lockedFundForCategoryFor[account][index] > 0, "BadDaysCrowdsale: No fund for this account");
        require(balanceOfLockedFundForCategoryFor[account][index] > 0, "BadDaysCrowdsale: Zero balance for this account");
        
        Category storage category = fundCategory[index];
        require(block.timestamp > dayOfTGE.add(category.lockPeriod.mul(1 seconds)), "BadDaysCrowdsale: Funds still locked");
        
        uint256 distMonth = getDistributionMonth();
        uint256 lockedMonths = (category.lockPeriod.mul(1 seconds).div(oneMonth)).add(1);
        
        uint256 claimable;
        if(block.timestamp > dayOfTGE.add(category.lockPeriod.mul(1 seconds))) {
            if(claimedTokensForTheMonth[account][index][distMonth] == 0) {
                for (uint256 i = lockedMonths; i <= distMonth; i++) {
                    if(claimedTokensForTheMonth[account][index][i] == 0) {
                        uint256 monthly = (lockedFundForCategoryFor[account][index].mul(category.percentClaimablePerMonth)).div(10000);
                        claimable = claimable.add(monthly);
                        claimedTokensForTheMonth[account][index][i] = monthly;
                        if (claimable >= balanceOfLockedFundForCategoryFor[account][index]) break;
                    }
                }
            }   
            if (claimable > 0) {
                if (claimable > balanceOfLockedFundForCategoryFor[account][index])
                    claimable = balanceOfLockedFundForCategoryFor[account][index];
                balanceOfLockedFundForCategoryFor[account][index] = balanceOfLockedFundForCategoryFor[account][index].sub(claimable);
                _token.transfer(account, claimable);
                emit WithdrawTokens(_msgSender(), account, claimable);
            }
        }
    }
    
    function switchWithdrawal(bool condition) external only(CREATOR_ROLE) {
        require(dayOfTGE > 0,"BadDaysCrowdsale: Missing TGE date");
        
        canWithdraw = condition;
        emit CanWithdraw(_msgSender(), canWithdraw);
    }
    
    function getDistributionMonth() public view returns(uint256) {
        require(dayOfTGE > 0,"BadDaysCrowdsale: Missing TGE date");
        return ((block.timestamp.sub(dayOfTGE)).div(oneMonth)).add(1);
    }
    
    function updateWhitelist(address[] memory accounts, bool mode) external only(CREATOR_ROLE) {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[accounts[i]] = mode;
        }
        emit UpdateWhitelist(_msgSender(), accounts, mode);
    }
    
    function isWhitelisted(address account) public view returns (bool) {
        return whitelisted[account];
    }
    
    function emergencyWithdraw() external whenPaused only(DEFAULT_ADMIN_ROLE) {
        uint256 balance = _token.balanceOf(address(this));
        if (balance > 0) {
            _token.transfer(getTokenWallet(), balance);
        }
    }

}