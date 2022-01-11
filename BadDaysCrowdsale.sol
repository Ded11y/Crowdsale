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

contract BadDaysCrowdsale is Pausable, CappedCrowdsale, TimedCrowdsale, ContextMixin, NativeMetaTransaction {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    string constant name = "BadDaysCrowdsale";
    
    //Whitelisted addresses that can engage in pre-sale 
    mapping(address => bool) internal whitelisted;
    
    //Constant counter for a month = 30 days = 2,592,000 seconds
    uint256 constant oneMonth = 2592000;

    //Contant counter for a day = 86400 seconds
    uint256 constant oneDay = 86400;
    
    //Account -> Category -> Amount Withdrawn after TGE for Category 7 through 11
    mapping(address => mapping(uint256 => uint256)) public claimedTokensAfterTGE;
    
    //Acocunt -> Category -> Day -> Amount
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public claimedTokensForTheDay;
    
    //Override control to enable withdrawal after TGE has been defined and the pre-sale has been closed
    bool internal canWithdraw;
    
    //Override date for the TGE - needs to be manually set
    uint256 public dayOfTGE;
    
    //MNFT token address
    IERC20 internal _maticWeth;
    
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
    
    //Holder of the address of the holder of the allocated fund per category (0 - 6)
    mapping(uint256 => address) public accountForCategory;
    
    //total reserved funds of a specific wallet
    mapping(address => uint256) public totalFunds;
    
    //total balance of an address
    mapping(address => uint256) public totalBalanceOfFunds;
    
    //total reserved funds of a specific wallet for a specific category
    mapping(address => mapping(uint256 => uint256)) public totalFundsForCategory;
    
    //balance of a specific address for a specific category
    mapping(address => mapping(uint256 => uint256)) public balanceOfFundsForCategory;
    
    //total balance of the main vault from start to end, across all categories
    uint256 public vaultBalance;
    
    //total balance of the vault of an ongoing sale category
    uint256 public presaleVaultBalance;
    
    //Vault balance for a specific category
    mapping(uint256 => uint256) public raisedVaultBalance;
    
    //Total raised funds across all catagories (7 - 11)
    uint256 public totalRaisedFunds;
    
    //Total raised funds for each category (7 - 11)
    mapping(uint256 => uint256) public raisedFundsForCategory;
    
    //Struct that defines the configurations of each Category
    struct Category {
        string desc;
        uint256 index;
        uint256 periodAfterTGE;
        uint256 percentClaimableAtTGE;
        uint256 vestingPeriodAfterTGE;
    }
    
    event SetPresaleSchedule(address sender, uint256 openingTime, uint256 closingTime, uint256 cap, uint256 rate, uint256 index);
    event WithdrawTokens(address sender, address beneficiary, uint256 amount);
    event TokensPurchased(address indexed purchaser, uint256 index, address indexed beneficiary, uint256 value, uint256 amount);
    event UpdateWhitelist(address sender, address[] accounts, bool mode);
    event ConfigCategory(string desc, uint256 index, uint256 periodAfterTGE, uint256 percentClaimableAtTGE, uint256 vestingPeriodAfterTGE);
    event LockAllocation(string desc, address account, uint256 amount, address sender);
    event SetTGE(address sender, uint256 value);
    event CanWithdraw(address sender, bool canWithdraw);
    event SendFundsAfterTGE(address account, uint256 category, uint256 claimable);
    event AllocateTokensFor(address sender, uint256 index, address account, uint256 amounts);
    
    constructor(
        MaticWETH maticWeth,
        address payable wallet,  // wallet to send Ether
        IERC20 token,            // the token
        address tokenwallet     // tokenWallet of the token
    )
        public
    {
        _setupContractId(name);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(CREATOR_ROLE, _msgSender());
        _wallet = wallet;
        _tokenWallet = tokenwallet;
        _token = token;
        _maticWeth = maticWeth;
        
        //desc, index, periodAfterTGE, percentClaimableAtTGE, vestingPeriodAfterTGE
        _configCategory("Team", 0, 15552000, 0, 1080);
        _configCategory("Operations", 1, 7776000, 0, 690);
        _configCategory("Marketing", 2, 7776000, 0, 690);
        _configCategory("Advisors", 3, 7776000, 0, 720);
        _configCategory("Growth Fund", 4, 15552000, 0, 780);
        _configCategory("Escrow Vault", 5, 2592000, 0, 0);
        _configCategory("Play Rewards", 6, 86400, 0, 630);
        _configCategory("Seed Round", 7, 5184000, 0, 450);
        _configCategory("Strategic Round", 8, 2592000, 0, 360);
        _configCategory("Private Round 1", 9, 1814400, 0, 240);
        _configCategory("Private Round 2", 10, 1209600, 0, 210);
        _configCategory("Public Round", 11, 604800, 15, 120);
        
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
    
    modifier whenCanWithdraw() {
        require(dayOfTGE > 0, "BadDaysCrowdsale: No TGE yet");
        require(hasClosed(), "BadDaysCrowdsale: not closed");
        require(canWithdraw, "BadDaysCrowdsale: Withdrawal is still disabled");
         _;
    }
    
    function isApprovedToSpend(address account) external view returns (uint256) {
        return _maticWeth.allowance(account, address(this));
    }
    
    function setTGE(uint256 value) external only(CREATOR_ROLE) {
        dayOfTGE = value;
        emit SetTGE(_msgSender(), value);
    } 
    
    /// @notice This fuction configures aech category for the token sale
    /// @param desc - name of the category
    /// @param index - base 0 index of the category
    /// @param periodAfterTGE - lock period after TGE in seconds
    /// @param vestingPeriodAfterTGE - total vesting period in days
    function _configCategory(string memory desc, uint256 index, uint256 periodAfterTGE, uint256 percentClaimableAtTGE, uint256 vestingPeriodAfterTGE) internal {
        fundCategory[index] = Category(
            desc,
            index,
            periodAfterTGE,
            percentClaimableAtTGE,
            vestingPeriodAfterTGE
        );
    }
    
    function configCategory(string memory desc, uint256 index, uint256 periodAfterTGE, uint256 percentClaimableAtTGE, uint256 vestingPeriodAfterTGE) 
    external only(CREATOR_ROLE) {
        _configCategory(desc, index, periodAfterTGE, percentClaimableAtTGE, vestingPeriodAfterTGE);
        emit ConfigCategory(desc, index, periodAfterTGE, percentClaimableAtTGE, vestingPeriodAfterTGE);
    }
    
    function getCategoryConfig(uint256 code) external view
    returns (string memory desc, uint256 index, uint256 periodAfterTGE, uint256 percentClaimableAtTGE, uint256 vestingPeriodAfterTGE) {
        Category storage category = fundCategory[code];

        return(category.desc, category.index, category.periodAfterTGE, category.percentClaimableAtTGE, category.vestingPeriodAfterTGE);
    }
    
    /**
     * @notice This opens a new category that will be available for pre-sale. Note that only Categories 7 through 11 could be opened for crowdsale.
     * @param openingTime - Opening time for the specific crowdsale in epoch seconds
     * @param closingTime - Closing time for the specific crowdsale in epoch seconds.
     * @param cap - Total cap in wei for the specific category
     * @param rate - Rate of token per wei
     * @param index - Index of the Category to be opened 
     */
    function setPresaleSchedule(uint256 openingTime, uint256 closingTime, uint256 cap, uint256 rate, uint256 index) external only(CREATOR_ROLE) {
        require(!isOpen(), "BadDaysCrowdsale: not closed");
        require(index > 6 && index < 12, "Invalid crowdsale index");
        
        activeCatIndex = index;
        presaleVaultBalance = 0;
        _weiRaised = 0;
        _cap = cap;
        _rate = rate;
        _setPresaleSchedule(openingTime, closingTime);
        
        emit SetPresaleSchedule(_msgSender(), openingTime, closingTime, cap, rate, index);
    }
    
    function allocateTokensFor(address[] memory accounts, uint256[] memory  amounts, uint256 index) external whenNotPaused only(CREATOR_ROLE) {
        require(index > 6 && index < 12, "BadDaysCrowdsale: No active category for crowdsale");
        require(accounts.length == amounts.length, "BadDaysCrowdsale: Number of accounts must mach number of amounts");

        for (uint256 i = 0; i < accounts.length; i++) {
            require(amounts[i] > 0, "BadDaysCrowdsale: amount must be more than 0");
            require(totalFunds[accounts[i]] == 0, "BadDaysCrowdsale: account already has funds");
            require(accounts[i] != address(0), "Crowdsale: beneficiary is the zero address");
        
            totalRaisedFunds = totalRaisedFunds.add(amounts[i]);
            raisedFundsForCategory[index] = raisedFundsForCategory[index].add(amounts[i]);
 
            _processPurchase(accounts[i], amounts[i], index);
            emit AllocateTokensFor(_msgSender(), index, accounts[i], amounts[i]);
        }
    }
    
    function buyTokens(address account, uint256 amount) public nonReentrant payable onlyWhileOpen whenNotPaused {
        require(isOpen(), "BadDaysCrowdsale: Still close");
        require(!capReached(), "BadDaysCrowdsale: Cap already reached");
        require(amount > 0, "BadDaysCrowdsale: amount must be more than 0");
        require(activeCatIndex == 11, "BadDaysCrowdsale: No active category for crowdsale");
        require(_maticWeth.balanceOf(_msgSender()) >= amount,"BadDaysCrowdsale: Not enough funds");
        uint256 allowance = _maticWeth.allowance(_msgSender(), address(this));
 	    require(allowance >= amount, "BadDaysCrowdsale: Not enough allowance.");
 	    
 	    require(_weiRaised.add(amount) <= cap(), "BadDaysCrowdsale: Amount will cause to exceed cap");
 	    require(account != address(0), "Crowdsale: beneficiary is the zero address");

        // collect fund
        _maticWeth.safeTransferFrom(_msgSender(), getWallet(), amount);
        
        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(amount);

        // update state
        _weiRaised = _weiRaised.add(amount);
        totalRaisedFunds = totalRaisedFunds.add(amount);
        raisedFundsForCategory[activeCatIndex] = raisedFundsForCategory[activeCatIndex].add(amount);

        _processPurchase(account, tokens, activeCatIndex);
        emit TokensPurchased(_msgSender(), activeCatIndex, account, amount, tokens);
    }
    
    /**
     * @dev Overrides parent by storing due balances, and delivering tokens to the vault instead of the end user. This
     * ensures that the tokens will be available by the time they are withdrawn (which may not be the case if
     * `_deliverTokens` was called later).
     * @param account - account to receive the tokens
     * @param tokenAmount Amount of tokens purchased
     */
    function _processPurchase(address account, uint256 tokenAmount, uint256 index) internal {
        uint256 allowance = _token.allowance(_tokenWallet, address(this));
        require(allowance >= tokenAmount, "BadDaysCrowdsale: Not enough allowance for contract.");
        
        _token.safeTransferFrom(_tokenWallet, address(this), tokenAmount);
        totalFunds[account] = totalFunds[account].add(tokenAmount);
        totalBalanceOfFunds[account] = totalBalanceOfFunds[account].add(tokenAmount);
        totalFundsForCategory[account][index] = totalFundsForCategory[account][index].add(tokenAmount);
        balanceOfFundsForCategory[account][index] = balanceOfFundsForCategory[account][index].add(tokenAmount);
        raisedVaultBalance[index] = raisedVaultBalance[index].add(tokenAmount);
        presaleVaultBalance = presaleVaultBalance.add(tokenAmount);
        vaultBalance = vaultBalance.add(tokenAmount);
    }
    
    function _computeClaimableAfterTGE(address account, uint256 index) internal view returns(uint256) {
        Category storage category = fundCategory[index];
        uint256 percentClaimableAtTGE = category.percentClaimableAtTGE;
  
        uint256 claimable;
        if(block.timestamp > dayOfTGE) { 
            if (percentClaimableAtTGE > 0 && claimedTokensAfterTGE[account][index] == 0) {
                claimable = (totalFundsForCategory[account][index].mul(percentClaimableAtTGE)).div(100);
            }
        }   
        return claimable;
    }
    
    function getClaimableAfterTGE(address account, uint256 category) public view whenCanWithdraw returns(uint256) {
        require(totalBalanceOfFunds[account] > 0, "BadDaysCrowdsale: No reserved funds");
        require(category >= 7 && category < 12, "BadDaysCrowdsale: Category must be 7 - 11");
        
        return _computeClaimableAfterTGE(account, category);
    }
    
    function _getDaily(uint256 index, address account) internal view returns (uint256) {
        Category storage category = fundCategory[index];
        uint256 totalPercentForDistribution = 100;
        
        //Compute the actual daily percentage
        if(category.percentClaimableAtTGE > 0) {
            totalPercentForDistribution = totalPercentForDistribution.sub(category.percentClaimableAtTGE);
        }

        uint256 dailyClaimable = (totalFundsForCategory[account][index].mul(totalPercentForDistribution)).div(category.vestingPeriodAfterTGE);
        return dailyClaimable;
    }

    function _getTotalDaily(uint256 index, address account, uint256 periodAfterTGE) internal view returns (uint256) {
        uint256 claimable;
        uint256 lockedDays = (periodAfterTGE.div(oneDay)).add(1);
        if(block.timestamp > (dayOfTGE.add(periodAfterTGE))) {
            if(claimedTokensForTheDay[account][index][getDistributionDay()] == 0) {
                for (uint256 i = lockedDays; i <= getDistributionDay(); i++) {
                    if(claimedTokensForTheDay[account][index][i] == 0) {
                        uint256 dailyClaimable = _getDaily(index, account);
                        claimable = claimable.add(dailyClaimable.div(100));
                    }

                    if(claimable >= balanceOfFundsForCategory[account][index]) {
                        claimable = balanceOfFundsForCategory[account][index];
                        break;
                    }               
                }
            }
        }
        return claimable;
    }
    
    function _getClaimableFunds(address account, uint256 index) internal view returns(uint256) {
        Category storage category = fundCategory[index];
        uint256 periodAfterTGE = category.periodAfterTGE;
        uint256 claimable = _getTotalDaily(index, account, periodAfterTGE);
        //Just in case there will be decimal rounding off results. 
        //To ensure exact values of remaining funds will be claimed.
        if(claimable > balanceOfFundsForCategory[account][index]) {
            claimable = balanceOfFundsForCategory[account][index];
        }
        return claimable;
    }
    
    function getClaimableForCategory(address account, uint256 index) public view returns(uint256) {
        uint256 claimable;
        if(balanceOfFundsForCategory[account][index] > 0) {
            claimable = _getClaimableFunds(account, index);
        }
        return claimable;
    }
    
    /**
     * @dev Withdraw tokens only after crowdsale ends.
     * @param account Whose tokens will be withdrawn.
     */
    function getClaimable(address account) public view whenCanWithdraw returns(uint256) {
        require(totalBalanceOfFunds[account] > 0, "BadDaysCrowdsale: No reserved funds");
        
        uint256 claimable;
        for (uint256 i = 7; i < 12; i++) {
            claimable = claimable.add(getClaimableForCategory(account, i));
        }
        return claimable;
    }

    function _updateDailyClaimable(uint256 index, address account, uint256 periodAfterTGE) internal returns (uint256) {
        uint256 claimable;
        uint256 lockedDays = (periodAfterTGE.div(oneDay)).add(1);
        if(block.timestamp > (dayOfTGE.add(periodAfterTGE))) {
            if(claimedTokensForTheDay[account][index][getDistributionDay()] == 0) {
                for (uint256 i = lockedDays; i <= getDistributionDay(); i++) {
                    if(claimedTokensForTheDay[account][index][i] == 0) {
                        uint256 dailyClaimable = _getDaily(index, account);
                        claimable = claimable.add(dailyClaimable.div(100));
                        claimedTokensForTheDay[account][index][i] = dailyClaimable;
                    }

                    if(claimable >= balanceOfFundsForCategory[account][index]) {
                        claimable = balanceOfFundsForCategory[account][index];
                        break;
                    }               
                }
            }
        }
        return claimable;
    }
    
    function _updateClaimable(address account) internal {
        uint256 amount;
        uint256 claimable;
        for (uint256 i = 7; i < 12; i++) {
            claimable = 0;
            if(balanceOfFundsForCategory[account][i] > 0) {
                Category storage category = fundCategory[i];
                uint256 periodAfterTGE = category.periodAfterTGE;
            
                //Compute the actual daily percentage
                uint256 percentClaimableAtTGE = category.percentClaimableAtTGE;
                uint256 totalPercentForDistribution = 100;
        
                if(percentClaimableAtTGE > 0) {
                    totalPercentForDistribution = totalPercentForDistribution.sub(percentClaimableAtTGE);
                }
                claimable = claimable.add(_updateDailyClaimable(i, account, periodAfterTGE));
                
                //Just in case there will be decimal rounding off results. 
                //To ensure exact values of remaining funds will be claimed.
                if(claimable > balanceOfFundsForCategory[account][i]) {
                    claimable = balanceOfFundsForCategory[account][i];
                }
                balanceOfFundsForCategory[account][i] = balanceOfFundsForCategory[account][i].sub(claimable);
            }
            amount = amount.add(claimable);
         }
         totalBalanceOfFunds[account] = totalBalanceOfFunds[account].sub(amount);
    }
    
    function sendFundsAfterTGE(address account, uint256 category) external whenCanWithdraw whenNotPaused only(CREATOR_ROLE) {
        require(totalBalanceOfFunds[account] > 0, "BadDaysCrowdsale: No reserved funds");
        
        uint256 claimable = getClaimableAfterTGE(account, category);
        if (claimable > 0) {
            claimedTokensAfterTGE[account][category] = claimable;
            balanceOfFundsForCategory[account][category] = balanceOfFundsForCategory[account][category].sub(claimable);
            totalBalanceOfFunds[account] = totalBalanceOfFunds[account].sub(claimable);
            _token.transfer(account, claimable);
            emit SendFundsAfterTGE(account, category, claimable);
        }
        else {
            revert("BadDaysCrowdsale: Nothing to send");
        }
    }
    
    function withdrawTokens(address account) whenCanWithdraw external whenNotPaused {
        require(totalBalanceOfFunds[account] > 0, "BadDaysCrowdsale: No due any tokens");
        
        uint256 claimable = getClaimable(account);
        if(claimable > 0) {
            _updateClaimable(account);
            _token.transfer(account, claimable);
            emit WithdrawTokens(_msgSender(), account, claimable);
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

    function getDistributionDay() public view returns(uint256) {
        require(dayOfTGE > 0,"BadDaysCrowdsale: Missing TGE date");
        return ((block.timestamp.sub(dayOfTGE)).div(oneDay)).add(1);
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
    
    function emergencyWithdraw(address account) external only(DEFAULT_ADMIN_ROLE) {
        uint256 balance = totalBalanceOfFunds[account];
        if (balance > 0) {
            totalBalanceOfFunds[account] = 0;
            for (uint256 i = 7; i < 12; i++) {
                balanceOfFundsForCategory[account][i] = 0;
            }
            _token.transfer(getTokenWallet(), balance);
        }
    }

}
