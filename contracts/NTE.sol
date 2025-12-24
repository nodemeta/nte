// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Node Meta Energy (NTE) - Advanced BEP20 Token
 * @author Node Meta Team
 * @notice Enterprise-grade token with comprehensive DeFi features, MEV protection, and security controls
 * @dev Implements BEP20 standard with tax system, auto-liquidity, anti-dump, and emergency controls
 * @custom:version 1.0.0
 * @custom:security-contact security@node-meta.com
 */

/*
 * ERROR CODE LEGEND
 * E01  Not owner
 * E02  Paused
 * E03  Reentrancy
 * E04  Owner zero
 * E05  Supply zero
 * E06  Router not contract
 * E07  Factory zero
 * E08  Factory not contract
 * E09  WETH zero
 * E10  WETH not contract
 * E11  Pair zero
 * E12  Pair setup failed
 * E13  Router pair check fail
 * E14  Router WETH call fail
 * E15  Router factory call fail
 * E16  Blacklisted
 * E17  Renounce locked 30d
 * E18  New owner zero
 * E19  Already owner
 * E20  Already pending
 * E21  Not pending owner
 * E22  Transfer delay
 * E23  No pending transfer
 * E24  Buy tax > 25%
 * E25  Sell tax > 25%
 * E26  Transfer tax > 25%
 * E27  Total tax > 50%
 * E28  Tax cooldown
 * E29  Buy tax change > 2.5%
 * E30  Sell tax change > 2.5%
 * E31  Transfer tax change > 2.5%
 * E32  Invalid address
 * E33  Cannot blacklist owner
 * E34  Cannot blacklist contract
 * E35  Zero address
 * E36  Same treasury
 * E37  Treasury blacklisted
 * E38  Percent 1-100
 * E39  Amount > 0
 * E40  Exceeds supply
 * E41  Amount < min
 * E42  Fee 0-100
 * E43  Threshold negative
 * E44  Threshold missing
 * E45  Slippage low
 * E46  Slippage high
 * E47  Slippage zero
 * E48  Min impact 0.1%
 * E49  Impact 0.1-100%
 * E50  Cooldown negative
 * E51  Cooldown > 1d
 * E52  Router not set
 * E53  No tokens
 * E54  Auto-liq paused
 * E55  Locking disabled
 * E56  Invalid pair
 * E57  Amount > 0 (lock)
 * E58  Lock period > 0
 * E59  Already locked
 * E60  Insufficient LP
 * E61  Transfer fail
 * E62  Not locked
 * E63  Still locked
 * E64  Invalid token
 * E65  Zero recipient
 * E66  Insufficient balance
 * E67  LP locked reserve
 * E68  Slippage exceeds
 * E69  Wait 30d
 * E70  Invalid recipient
 * E71  Insufficient BNB
 * E72  BNB transfer fail
 * E73  Circuit not triggered
 * E74  Max blocks high
 * E75  Min time high
 * E76  Mint to zero
 * E77  Burn from zero
 * E78  Burn exceeds bal
 * E79  From zero
 * E80  To zero
 * E81  Sender blacklisted
 * E82  Recipient blacklisted
 * E83  Exceeds balance
 * E84  Approve from zero
 * E85  Approve to zero
 * E86  Overflow
 * E87  Allowance below zero
 * E88  Insufficient allowance
 * E89  Transfers paused
 * E90  MEV: too frequent
 * E91  MEV: too fast
 * E92  MEV: DEX interval
 * E93  Exceeds max tx
 * E94  Balance overflow
 * E95  Exceeds max wallet
 * E96  Sender cooldown
 * E97  Recipient cooldown
 * E98  Price impact high
 * E99  Exceeds anti-dump
 * E100 Sell cooldown
 * E101 Anti-bot active
 * E102 Accumulated overflow
 * E103 Tax accounting
 * E104 Router not validated
 * E105 Slippage max
 * E106 Total liquidity overflow
 * 
 * EVENT MESSAGE CODES (for emit statements)
 * M01  Treasury updated
 * M02  Circuit breaker reset
 * M03  MEV: block interval
 * M04  MEV: time interval
 * M05  MEV: DEX block interval
 * M06  Swap: invalid amounts
 * M07  Swap: unknown error
 * M08  Swap: get amounts fail
 * M09  Circuit: slippage fails
 * M10  Liquidity: add failed
 * M11  Liquidity: unknown error
 * M12  Liquidity: swap failed
 */

/// @title PancakeSwap Router Interface
/// @notice Interface for PancakeSwap Router V2 operations
interface IPancakeRouter {
    /// @notice Returns factory contract address
    function factory() external pure returns (address);
    /// @notice Returns WETH contract address  
    function WETH() external pure returns (address);
    /// @notice Swap tokens for ETH supporting fee-on-transfer tokens
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    /// @notice Add liquidity for ETH pairs
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    /// @notice Get amounts out for given input amount and path
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

/// @title PancakeSwap Factory Interface
/// @notice Interface for PancakeSwap Factory V2 operations  
interface IPancakeFactory {
    /// @notice Creates a pair for two tokens
    function createPair(address tokenA, address tokenB) external returns (address pair);
    /// @notice Returns pair address for two tokens
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @title Standard ERC20 Interface
/// @notice Standard interface for ERC20 token operations
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract NTE is IERC20 {
    
    // ===================================================
    // STATE VARIABLES
    // ===================================================
    
    /// @notice ERC20 token balances mapping
    mapping(address => uint256) private _balances;
    /// @notice ERC20 allowances mapping (owner => spender => amount)
    mapping(address => mapping(address => uint256)) private _allowances;
    /// @notice Total token supply
    uint256 private _totalSupply;
    
    /// @notice Contract owner address
    address private _owner;
    
    /// @notice Contract pause state for emergency control
    bool private _paused;
    
    /// @notice Treasury wallet receiving tax payments
    address public treasury;
    
    /// @notice Buy tax in basis points (1 bp = 0.01%)
    uint256 public buyTaxBps;
    /// @notice Sell tax in basis points (1 bp = 0.01%)
    uint256 public sellTaxBps;
    /// @notice Transfer tax in basis points (1 bp = 0.01%)
    uint256 public transferTaxBps;
    
    /// @notice PancakeSwap router contract address
    address public pancakeRouter;
    /// @notice Main trading pair address (NTE/WETH)
    address public pancakePair;
    /// @notice Mapping of addresses recognized as trading pairs
    mapping(address => bool) public isPancakePair;
    
    /// @notice Anti-bot protection enabled state
    bool public antiBotEnabled;
    /// @notice Contract deployment timestamp
    uint256 public launchTime;
    /// @notice Anti-bot protection duration in seconds
    uint256 public antiBotDuration;
    
    /// @notice Token name
    string private _name;
    /// @notice Token symbol
    string private _symbol;
    /// @notice Token decimals
    uint8 private _decimals;
    /// @notice Token logo URL for metadata
    string private _tokenLogo;
    /// @notice Token description for metadata
    string private _description;
    /// @notice Official website URL
    string private _website;
    
    /// @notice Anti-dump protection enabled state
    bool public antiDumpEnabled;
    /// @notice Maximum percentage of supply sellable per transaction
    uint256 public maxSellPercentage;
    /// @notice Cooldown period between large sells
    uint256 public sellCooldown;
    
    /// @notice Tax exempt addresses (no fees applied)
    mapping(address => bool) public taxExempt;
    
    /// @notice Liquidity lock information structure
    /// @dev Stores details about locked LP tokens to prevent rug pulls
    struct LiquidityLock {
        uint256 amount;        /// Amount of LP tokens locked
        uint256 lockTime;      /// Timestamp when locked
        uint256 unlockTime;    /// Timestamp when unlockable
        bool isLocked;         /// Current lock status
        address locker;        /// Address that locked the tokens
    }
    /// @notice Mapping of LP token addresses to their lock info
    mapping(address => LiquidityLock) public liquidityLocks;
    /// @notice Global liquidity lock feature enabled state
    bool public liquidityLockEnabled;
    
    /// @notice Auto-liquidity feature enabled state
    bool public autoLiquidityEnabled;
    /// @notice Percentage of tax allocated to liquidity (0-100)
    uint256 public liquidityFeePercent;
    /// @notice Minimum tokens required to trigger auto-liquidity
    uint256 public liquidityThreshold;
    /// @notice Tokens accumulated for next liquidity addition
    uint256 public accumulatedLiquidityTokens;
    /// @notice Reentrancy guard for liquidity operations
    bool private inSwapAndLiquify;
    /// @notice Total tokens converted to liquidity since deployment
    uint256 public totalLiquidityAdded;
    /// @notice Timestamp of last liquidity addition
    uint256 public lastLiquidityAddTime;
    /// @notice Slippage tolerance for auto-liquidity swaps (basis points)
    uint256 public autoLiquiditySlippageBps;
    
    /// @notice Price impact protection enabled state
    bool public priceImpactLimitEnabled;
    /// @notice Maximum allowed price impact in basis points
    uint256 public maxPriceImpactPercent;
    /// @notice Addresses exempt from price impact limits
    mapping(address => bool) public priceImpactExempt;
    
    /// @notice Wallet cooldown system enabled state
    bool public walletCooldownEnabled;
    /// @notice Global cooldown time between trades (seconds)
    uint256 public globalCooldownSeconds;
    /// @notice Last trade timestamp per wallet
    mapping(address => uint256) public lastTradeTime;
    
    /// @notice Reentrancy protection flag
    bool private _entered;
    /// @notice Emergency pause state for auto-liquidity
    bool public autoLiquidityPaused;

    
    /// @notice Minimum allowed slippage (0.1%)
    uint256 private constant MIN_SLIPPAGE_BPS = 10;
    /// @notice Maximum allowed slippage (10%)
    uint256 private constant MAX_SLIPPAGE_BPS = 1000;
    /// @notice Threshold for dynamic slippage calculation
    uint256 private constant DYNAMIC_SLIPPAGE_THRESHOLD = 1000 * 10**18;
    /// @notice High volume slippage setting (2%)
    uint256 private constant HIGH_VOLUME_SLIPPAGE = 200;
    /// @notice Low volume slippage setting (5%)
    uint256 private constant LOW_VOLUME_SLIPPAGE = 500;
    /// @notice Maximum cooldown duration (1 day)
    uint256 private constant MAX_COOLDOWN = 86400;
    /// @notice Absolute maximum slippage allowed (20%)
    uint256 private constant ABSOLUTE_MAX_SLIPPAGE = 2000;
    /// @notice Current maximum allowed slippage (10% default)
    uint256 public maxAllowedSlippage = 1000;
    /// @notice Basis points constant (10000 = 100%)
    uint256 private constant BASIS_POINTS = 10000;

    
    /// @notice Last timestamp when taxes were changed
    uint256 private _lastTaxChangeTime;
    /// @notice Cooldown period between tax changes (1 day)
    uint256 private constant TAX_CHANGE_COOLDOWN = 1 days;
    
    /// @notice Whether owner is also paused during contract pause
    bool public pauseIncludesOwner;
    
    /// @notice Consecutive slippage failure counter
    uint256 private _consecutiveSlippageFailures;
    /// @notice Maximum failures before circuit breaker (3)
    uint256 private constant MAX_CONSECUTIVE_FAILURES = 3;
    
    /// @notice Validated router addresses mapping
    mapping(address => bool) private _validatedRouters;
    
    /// @notice MEV protection enabled state
    bool public mevProtectionEnabled;
    /// @notice Maximum blocks between transactions for MEV detection
    uint256 public maxBlocksForMevProtection;
    /// @notice Last block number per wallet for MEV tracking
    mapping(address => uint256) public lastBlockNumber;
    /// @notice Addresses exempt from MEV protection
    mapping(address => bool) public mevProtectionExempt;
    /// @notice Minimum time between transactions (seconds)
    uint256 public minTimeBetweenTxs;

    // ===================================================
    // EVENTS
    // ===================================================
    
    /// @notice Emitted when contract ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when contract is paused
    event Paused(address account);
    /// @notice Emitted when contract is unpaused
    event Unpaused(address account);
    /// @notice Emitted when tax exemption status changes
    event TaxExemptUpdated(address account, bool exempt);
    /// @notice Emitted when token name and symbol are updated
    event NameSymbolUpdated(string newName, string newSymbol);
    /// @notice Emitted when token metadata is updated
    event MetadataUpdated(string tokenURI);
    /// @notice Emitted when PancakeSwap router is updated
    event PancakeRouterUpdated(address newRouter);
    /// @notice Emitted when anti-bot configuration changes
    event AntiBotConfigUpdated(bool enabled, uint256 duration);
    /// @notice Emitted when anti-dump configuration changes
    event AntiDumpConfigUpdated(bool enabled, uint256 maxPercentage, uint256 cooldown);
    /// @notice Emitted when liquidity is locked
    event LiquidityLocked(address indexed pair, uint256 amount, uint256 unlockTime);
    /// @notice Emitted when liquidity is unlocked
    event LiquidityUnlocked(address indexed pair, uint256 amount);
    /// @notice Emitted when auto-liquidity configuration changes
    event AutoLiquidityConfigUpdated(bool enabled, uint256 feePercent, uint256 threshold);
    /// @notice Emitted when auto-liquidity slippage is updated
    event AutoLiquiditySlippageUpdated(uint256 newSlippageBps);
    /// @notice Emitted when price impact limit configuration changes
    event PriceImpactLimitConfigUpdated(bool enabled, uint256 maxImpact);
    /// @notice Emitted when price impact exemption status changes
    event PriceImpactExemptUpdated(address indexed account, bool exempt);
    /// @notice Emitted when wallet cooldown configuration changes
    event WalletCooldownConfigUpdated(bool enabled, uint256 cooldownSeconds);
    /// @notice Emitted when tax exemption is batch updated
    event TaxExemptBatchUpdated(address[] accounts, bool exempt);
    /// @notice Emitted when maximum slippage is updated
    event MaxSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    /// @notice Emitted when swap operation is attempted
    event SwapAttempted(uint256 amount, uint256 slippageBps, bool success);
    /// @notice Emitted when swap operation fails
    event SwapFailed(uint256 amount, string reason);
    /// @notice Emitted when liquidity is successfully added
    event LiquidityAdded(uint256 amountToken, uint256 amountETH, uint256 liquidity);
    /// @notice Emitted when liquidity operation fails
    event LiquidityOperationFailed(string operation, string reason);
    /// @notice Emitted when BNB is received by the contract
    event BNBReceived(address indexed sender, uint256 amount);
    /// @notice Emitted when pair status is updated
    event PairStatusUpdated(address indexed pair, bool isPair);
    /// @notice Emitted when circuit breaker is triggered
    event CircuitBreakerTriggered(string reason);
    /// @notice Emitted when tax change is rate limited
    event TaxChangeRateLimited(uint256 attemptedChange, uint256 allowedChange);
    
    /// @notice Emitted when MEV protection configuration changes
    event MevProtectionConfigured(bool enabled, uint256 maxBlocks, uint256 minTime);
    /// @notice Emitted when MEV attack is prevented
    event MevAttackPrevented(address indexed account, uint256 blockNumber, string reason);
    /// @notice Emitted when MEV protection exemption status changes
    event MevProtectionExemptUpdated(address indexed account, bool exempt);

    // ===================================================
    // MODIFIERS
    // ===================================================
    
    /// @notice Restricts function access to contract Owner
    modifier onlyOwner() {
        require(msg.sender == _owner, "E01");
        _;
    }
    
    /// @notice Restricts function execution when contract is not paused
    modifier whenNotPaused() {
        require(!_paused, "E02");
        _;
    }
    
    /// @notice Prevents recursive calls during liquidity operations
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    /// @notice Simple reentrancy guard protection
    modifier nonReentrant() {
        require(!_entered, "E03");
        _entered = true;
        _;
        _entered = false;
    }
    
    // ===================================================
    // CONSTRUCTOR
    // ===================================================
    
    /**
     * @notice Initializes the NTE token contract with specified parameters
     * @dev Sets up token metadata, tax system, PancakeSwap integration, and security features
     * @param initialSupply Total tokens to create (without decimals, will be multiplied by 10^18)
     * @param initialOwner Address that will own and control the contract
     * @param _treasury Address that will receive tax payments (falls back to owner if zero)
     * @param _pancakeRouter PancakeSwap router address for DEX integration (optional)
     */
    constructor(
        uint256 initialSupply,
        address initialOwner,
        address _treasury,
        address _pancakeRouter
    ) {
        // Validate inputs
    require(initialOwner != address(0), "E04");
    require(initialSupply > 0, "E05");
        
        // Set owner
        _owner = initialOwner;
        
        // Set token info
        _name = "Node Meta Energy";
        _symbol = "NTE";
        _decimals = 18;
        
        // Setup tax system
        treasury = _treasury != address(0) ? _treasury : initialOwner;
        
        // Basis points system (1 bp = 0.01%)
        buyTaxBps = 200;        // 200 bp = 2% on buys
        sellTaxBps = 200;       // 200 bp = 2% on sells
        transferTaxBps = 300;   // 300 bp = 3% on transfers
        
        // Setup PancakeSwap if router provided
        if (_pancakeRouter != address(0)) {
            require(_isContract(_pancakeRouter), "E06");
            
            // Enhanced router validation
            try IPancakeRouter(_pancakeRouter).factory() returns (address factory) {
                require(factory != address(0), "E07");
                require(_isContract(factory), "E08");
                
                try IPancakeRouter(_pancakeRouter).WETH() returns (address weth) {
                    require(weth != address(0), "E09");
                    require(_isContract(weth), "E10");
                    
                    // Additional security: check if router and factory are on the same network
                    try IPancakeFactory(factory).getPair(address(this), weth) returns (address existingPair) {
                        if (existingPair != address(0)) {
                            // Pair already exists, use it
                            pancakePair = existingPair;
                            isPancakePair[pancakePair] = true;
                        } else {
                            // Create new pair - if this fails, revert to ensure valid deployment
                            address newPair = IPancakeFactory(factory).createPair(address(this), weth);
                            require(newPair != address(0), "E11");
                            pancakePair = newPair;
                            isPancakePair[pancakePair] = true;
                        }
                        
                        // Only set router if we successfully have a pair
                        require(pancakePair != address(0), "E12");
                        pancakeRouter = _pancakeRouter;
                        taxExempt[_pancakeRouter] = true;
                        _validatedRouters[_pancakeRouter] = true;
                    } catch {
                        revert("E13");
                    }
                } catch {
                    revert("E14");
                }
            } catch {
                revert("E15");
            }
        }
        
        // Set branding
        _tokenLogo = "https://node-meta.com/logo/node-meta.png";
        _description = "Node Meta Energy (NTE) - Revolutionary Blockchain Technology";
        _website = "https://node-meta.com";
        
        
        // Disable anti-dump
        antiDumpEnabled = false;
        maxSellPercentage = 100;
        sellCooldown = 0;
        
        // Disable liquidity locking
        liquidityLockEnabled = false;
        
        // Initialize Auto-Liquidity (disabled by default)
        autoLiquidityEnabled = false;
        liquidityFeePercent = 0;              // 0% to liquidity initially
        liquidityThreshold = 1000 * 10 ** 18; // 1000 tokens threshold
        accumulatedLiquidityTokens = 0;
        totalLiquidityAdded = 0;
        lastLiquidityAddTime = block.timestamp;
        autoLiquiditySlippageBps = 200;       // Default 2% slippage for auto-liquidity
        
        // Initialize Price Impact Limits (disabled by default)
        priceImpactLimitEnabled = false;
        maxPriceImpactPercent = 500;          // 5% max price impact
        
        // Initialize Wallet Cooldown (disabled by default)
        walletCooldownEnabled = false;
        globalCooldownSeconds = 30;           // 30 seconds default cooldown
        
        // Initialize MEV Protection (enabled by default)
        mevProtectionEnabled = true;
        maxBlocksForMevProtection = 2;        // 2 blocks
        minTimeBetweenTxs = 12;               // 12 seconds minimum between transactions
        
        // Enable anti-bot for 65 minutes
        antiBotEnabled = true;
        antiBotDuration = 3900;  // 65 minutes
        launchTime = block.timestamp;
        
        // Create initial supply
        _mint(initialOwner, initialSupply * 10 ** _decimals);
    }
    
    // ===================================================
    // PUBLIC FUNCTIONS - Standard ERC20 & View Functions
    // ===================================================
    
    /**
     * @notice Returns the token name
     * @dev Standard ERC20 function for display purposes
     * @return Token name string
     */
    function name() public view returns (string memory) {
        return _name;
    }
    
    /**
     * @notice Returns the token symbol
     * @dev Standard ERC20 function for display purposes
     * @return Token symbol string
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    /**
     * @notice Returns the number of decimal places
     * @dev Standard ERC20 function, determines token precision
     * @return Number of decimal places (18)
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Returns the total token supply
     * @dev Standard ERC20 function
     * @return Total number of tokens in existence
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @notice Returns the token balance of an account
     * @dev Standard ERC20 function
     * @param account Address to check balance for
     * @return Token balance of the account
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @notice Transfer tokens to another address
     * @dev Standard ERC20 transfer with tax logic applied
     * @param to Recipient address
     * @param amount Number of tokens to transfer
     * @return True if transfer succeeds
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithTax(msg.sender, to, amount);
        return true;
    }
    
    /**
     * @notice Returns the remaining number of tokens that spender is allowed to spend
     * @dev Standard ERC20 allowance function
     * @param account Token owner address
     * @param spender Address allowed to spend tokens
     * @return Remaining allowance amount
     */
    function allowance(address account, address spender) public view override returns (uint256) {
        return _allowances[account][spender];
    }
    
    /**
     * @notice Approve another address to spend tokens on your behalf
     * @param spender Address to approve for spending
     * @param amount Maximum amount to approve
     * @return True if approval succeeds
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @notice Transfer tokens from one address to another using allowance
     * @dev Standard ERC20 transferFrom with tax logic applied
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Number of tokens to transfer
     * @return True if transfer succeeds
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferWithTax(from, to, amount);
        return true;
    }

    // ===================================================
    // CUSTOM TRANSFER FUNCTIONS - Show on BscScan
    // ===================================================
    
    /**
     * @notice Transfer tokens for purchase
     * @dev Shows as "Buy" on BscScan - same as transfer but with custom event
     * @param to Recipient address
     * @param amount Number of tokens to transfer
     * @return True if transfer succeeds
     */
  /*   function Purchase(address to, uint256 amount) external returns (bool) {
        _transferWithTax(msg.sender, to, amount);
        return true;
    }
    */
    
    /**
     * @notice Claim
     * @dev Shows as "Claim" on BscScan
     * @param to Recipient address (usually caller's wallet)
     * @param amount Number of tokens to claim
     * @return True if transfer succeeds
     */
 /*    function Claim(address to, uint256 amount) external returns (bool) {
        _transferWithTax(msg.sender, to, amount);
        return true;
    }
 */
    /**
     * @notice Burn (permanently destroy) your own tokens
     * @dev Reduces total supply by burning tokens from sender's balance
     * @param amount Number of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    /**
     * @notice Check if the contract is currently paused
     * @dev Returns pause state for emergency control
     * @return True if contract is paused
     */
    function paused() public view returns (bool) {
        return _paused;
    }
    
    /**
     * @notice Returns the current contract owner
     * @dev Shows who has administrative control
     * @return Current owner address
     */
    function owner() public view returns (address) {
        return _owner;
    }
    
    /**
     * @notice Returns the token logo URL
     * @dev Used for metadata display in wallets and explorers
     * @return Token logo URL string
     */
    function tokenURI() public view returns (string memory) {
        return _tokenLogo;
    }
    
    /**
     * @notice Returns comprehensive token information
     * @dev Provides all basic token details for display purposes
     * @return tokenName Current token name
     * @return tokenSymbol Current token symbol  
     * @return tokenDecimals Number of decimal places
     * @return tokenTotalSupply Current total supply
     * @return logo Token logo URL
     * @return description Token description
     * @return website Official website URL
     */
    function getTokenInfo() public view returns (
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 tokenTotalSupply,
        string memory logo,
        string memory description,
        string memory website
    ) {
        return (_name, _symbol, _decimals, _totalSupply, _tokenLogo, _description, _website);
    }
    
    /**
     * @notice Returns current tax configuration settings in basis points
     * @dev Shows precise tax rates and exempt addresses
     * @return buyTax Current buy tax in basis points
     * @return sellTax Current sell tax in basis points
     * @return transferTax Current transfer tax in basis points
     * @return treasuryAddr Treasury address receiving tax proceeds
     * @return routerExempt Whether router is tax exempt
     * @return pairExempt Whether main pair is tax exempt
     */
    function getTaxConfiguration() public view returns (
        uint256 buyTax,
        uint256 sellTax,
        uint256 transferTax,
        address treasuryAddr,
        bool routerExempt,
        bool pairExempt
    ) {
        return (
            buyTaxBps,
            sellTaxBps,
            transferTaxBps,
            treasury,
            taxExempt[pancakeRouter],
            taxExempt[pancakePair]
        );
    }
    
    // ============================================
    // ADMIN FUNCTIONS - Only Owner Can Call
    // ============================================
    
    /**
     * @notice Owner: Pauses all token transfers and trading
     * @dev Emergency function to stop all token operations
     * @param includeOwner If true, owner is also paused; if false, owner can still transact
     */
    function pause(bool includeOwner) external onlyOwner {
        _paused = true;
        pauseIncludesOwner = includeOwner;
        emit Paused(msg.sender);
    }
    
    /**
     * @notice Owner: Resumes normal token operations after pause
     * @dev Restores all transfer and trading functionality
     */
    function unpause() external onlyOwner {
        _paused = false;
        pauseIncludesOwner = false;
        emit Unpaused(msg.sender);
    }
    
    /**
     * @notice Owner: Permanently renounces ownership (IRREVERSIBLE)
     * @dev Can only be called 30 days after launch for safety
     */
    function renounceOwnership() public onlyOwner {
        require(block.timestamp > launchTime + 30 days, "E17");
        address previousOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }
    
    /**
     * @notice Owner: Transfers ownership in a single step
     * @dev Replaces the previous 2-step flow to reduce size and complexity
     * @param newOwner Address of the new owner (cannot be zero or current owner)
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "E18");
        require(newOwner != _owner, "E19");
        address previousOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
    
    /**
     * @notice Owner: Sets tax rates using basis points for precision
     * @dev Allows precise tax control with 0.01% increments
     * @param newBuyTaxBps Buy tax in basis points (0-2500, 150 = 1.5%)
     * @param newSellTaxBps Sell tax in basis points (0-2500, 250 = 2.5%)
     * @param newTransferTaxBps Transfer tax in basis points (0-2500)
     */
    function setAllTaxBasisPoints(
        uint256 newBuyTaxBps,
        uint256 newSellTaxBps,
        uint256 newTransferTaxBps
    ) external onlyOwner {
    require(newBuyTaxBps <= 2500, "E24");
    require(newSellTaxBps <= 2500, "E25");
    require(newTransferTaxBps <= 2500, "E26");
        
        // Total tax validation - max 50% (5000 bp) combined
    require(newBuyTaxBps + newSellTaxBps + newTransferTaxBps <= 5000, "E27");
        
        // Rate limiting - prevent rapid tax changes
    require(block.timestamp >= _lastTaxChangeTime + TAX_CHANGE_COOLDOWN, "E28");
        
        // Limit individual tax changes (250 bp = 2.5% max change per update)
        uint256 buyChange = newBuyTaxBps > buyTaxBps ? 
            newBuyTaxBps - buyTaxBps : buyTaxBps - newBuyTaxBps;
        uint256 sellChange = newSellTaxBps > sellTaxBps ? 
            newSellTaxBps - sellTaxBps : sellTaxBps - newSellTaxBps;
        uint256 transferChange = newTransferTaxBps > transferTaxBps ? 
            newTransferTaxBps - transferTaxBps : transferTaxBps - newTransferTaxBps;
        
    require(buyChange <= 250, "E29");
    require(sellChange <= 250, "E30");
    require(transferChange <= 250, "E31");
        
        buyTaxBps = newBuyTaxBps;
        sellTaxBps = newSellTaxBps;
        transferTaxBps = newTransferTaxBps;
        
        _lastTaxChangeTime = block.timestamp;
    }
    
    /**
     * @notice Owner: Adds or removes tax exemption for address
     * @dev Exempt addresses don't pay taxes on transfers
     * @param user Wallet address to modify exemption for
     * @param exempt True to exempt, false to apply normal taxes
     */
    function setTaxExempt(address user, bool exempt) external onlyOwner {
        require(user != address(0), "E32");
        taxExempt[user] = exempt;
        emit TaxExemptUpdated(user, exempt);
    }
    


    /**
     * @notice Owner: Updates treasury address for tax payments
     * @dev Changes where tax revenue is sent for future collections
     * @param newTreasury New wallet address to receive tax payments
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "E35");
        require(newTreasury != treasury, "E36");
        treasury = newTreasury;
        emit MetadataUpdated("M01");
    }
    
    
    
    /**
     * @notice Owner: Configure anti-dump protection to prevent large price crashes.
     * @dev Set limits on how much of the total supply can be sold at once and cooldown periods.
     * @param enabled True to enable anti-dump protection, false to disable.
     * @param maxPercentage Maximum percentage of total supply sellable per transaction (0-100).
     * @param cooldownTime Seconds users must wait between large sells.
     */
    function setAntiDumpConfig(bool enabled, uint256 maxPercentage, uint256 cooldownTime) external onlyOwner {
        require(maxPercentage > 0 && maxPercentage <= 100, "E38");
        
        antiDumpEnabled = enabled;
        maxSellPercentage = maxPercentage;
        sellCooldown = cooldownTime;
        emit AntiDumpConfigUpdated(enabled, maxPercentage, cooldownTime);
    }
 
    
    /**
     * @notice Owner: Configure automatic liquidity addition system
     * @dev Enable/disable auto-liquidity and set parameters for automatic LP token creation
     * @param enabled True to enable auto-liquidity, false to disable
     * @param feePercent Percentage of tax allocated to liquidity (0-100)
     * @param threshold Minimum tokens required before triggering auto-liquidity
     * 
     * Example: setAutoLiquidityConfig(true, 50, 1000 * 10**18)
     * This allocates 50% of collected taxes to liquidity, triggers at 1000 tokens
     */
    function setAutoLiquidityConfig(
        bool enabled,
        uint256 feePercent,
        uint256 threshold
    ) external onlyOwner {
        require(feePercent >= 0 && feePercent <= 100, "E42");
        require(threshold >= 0, "E43");
        require(threshold > 0 || !enabled, "E44");
        
        autoLiquidityEnabled = enabled;
        liquidityFeePercent = feePercent;
        liquidityThreshold = threshold;
        
        emit AutoLiquidityConfigUpdated(enabled, feePercent, threshold);
    }
    
    /**
     * @notice Owner: Configure slippage for auto-liquidity swaps
     * @dev Set the maximum allowed slippage for automated swaps to prevent front-running
     * @param newSlippageBps Slippage in basis points (e.g., 50 = 0.5%, 200 = 2%)
     * 
     * Example: setAutoLiquiditySlippage(200)
     * This sets a 2% slippage tolerance for auto-liquidity swaps
     */
    function setAutoLiquiditySlippage(uint256 newSlippageBps) external onlyOwner {
        require(newSlippageBps >= MIN_SLIPPAGE_BPS, "E45");
        require(newSlippageBps <= MAX_SLIPPAGE_BPS, "E46");
        require(newSlippageBps > 0, "E47");
        autoLiquiditySlippageBps = newSlippageBps;
        emit AutoLiquiditySlippageUpdated(newSlippageBps);
    }
    
    /**
     * @notice Owner: Configure price impact protection limits
     * @dev Set maximum allowed price impact for trades to prevent large dumps
     * @param enabled True to enable price impact limits, false to disable
     * @param maxImpactBasisPoints Maximum price impact in basis points (100 = 1%, 500 = 5%)
     * 
     * Example: setPriceImpactLimitConfig(true, 500)
     * This limits any trade to max 5% price impact
     */
    function setPriceImpactLimitConfig(
        bool enabled,
        uint256 maxImpactBasisPoints
    ) external onlyOwner {
        require(maxImpactBasisPoints >= 10 || !enabled, "E48");
        require(maxImpactBasisPoints <= 10000, "E49");
        
        priceImpactLimitEnabled = enabled;
        maxPriceImpactPercent = maxImpactBasisPoints;
        
        emit PriceImpactLimitConfigUpdated(enabled, maxImpactBasisPoints);
    }
    
    /**
     * @notice Owner: Exempt specific addresses from price impact limits
     * @dev Allow certain addresses (like owner, treasury) to bypass price impact checks
     * @param account Address to exempt or un-exempt
     * @param exempt True to exempt from price impact limits, false to apply normal limits
     * 
     * Example: setPriceImpactExempt(treasuryAddress, true)
     */
    function setPriceImpactExempt(address account, bool exempt) external onlyOwner {
        require(account != address(0), "E32");
        priceImpactExempt[account] = exempt;
        emit PriceImpactExemptUpdated(account, exempt);
    }
    
    /**
     * @notice Owner: Configures wallet cooldown system
     * @dev Sets cooldown period between trades to prevent bot spam
     * @param enabled True to enable cooldown, false to disable
     * @param cooldownSeconds Global cooldown time in seconds
     */
    function setWalletCooldownConfig(bool enabled, uint256 cooldownSeconds) external onlyOwner {
        require(cooldownSeconds >= 0, "E50");
        require(cooldownSeconds <= MAX_COOLDOWN, "E51"); 
        
        walletCooldownEnabled = enabled;
        globalCooldownSeconds = cooldownSeconds;
        emit WalletCooldownConfigUpdated(enabled, cooldownSeconds);
    }
    
    /**
     * @notice Owner: Manually trigger liquidity addition
     * @dev Force auto-liquidity operation even if threshold not reached
     * 
     * Use this to manually add accumulated tokens to liquidity pool
     */
    function manualSwapAndLiquify() external onlyOwner nonReentrant {
        require(pancakeRouter != address(0), "E52");
        require(accumulatedLiquidityTokens > 0, "E53");
        require(!autoLiquidityPaused, "E54");
        _swapAndLiquify(accumulatedLiquidityTokens);
    }
    
    /**
     * @notice Owner: Lock liquidity pair tokens to prevent rug pulls and build trust.
     * @dev Locks LP tokens in this contract for a specified time period. Locked tokens cannot be withdrawn early.
     * @param pair The address of the liquidity pair (LP token contract address).
     * @param amount Number of LP tokens to lock (in wei, check LP token decimals).
     * @param lockPeriod How long to lock the tokens (in seconds, e.g., 31536000 = 1 year).
     */
    function lockLiquidity(address pair, uint256 amount, uint256 lockPeriod) external onlyOwner nonReentrant {
        require(liquidityLockEnabled, "E55");
        require(pair != address(0), "E56");
        require(amount > 0, "E57");
        require(lockPeriod > 0, "E58");
        require(!liquidityLocks[pair].isLocked, "E59");
        
        IERC20 lpToken = IERC20(pair);
    require(lpToken.balanceOf(msg.sender) >= amount, "E60");
        
        // EFFECTS: Update state BEFORE external call (CEI pattern)
        // This prevents re-entrancy by marking the pair as locked before the transfer
        uint256 unlockTime = block.timestamp + lockPeriod;
        liquidityLocks[pair] = LiquidityLock({
            amount: amount,
            lockTime: block.timestamp,
            unlockTime: unlockTime,
            isLocked: true,
            locker: msg.sender
        });
        
        // INTERACTIONS: External call AFTER state update
        // If this fails, the transaction reverts and state is rolled back
    require(lpToken.transferFrom(msg.sender, address(this), amount), "E61");
        
        emit LiquidityLocked(pair, amount, unlockTime);
    }
    
    /**
     * @notice Owner: Unlock previously locked liquidity tokens after lock period expires.
     * @dev Retrieve locked LP tokens once the lock period has ended. Cannot unlock early.
     * @param pair The liquidity pair address that has locked tokens.
     */
    function unlockLiquidity(address pair) external onlyOwner nonReentrant {
        LiquidityLock storage lock = liquidityLocks[pair];
    require(lock.isLocked, "E62");
    require(block.timestamp >= lock.unlockTime, "E63");
        
        uint256 amount = lock.amount;
        lock.isLocked = false;
        lock.amount = 0;
        
        IERC20(pair).transfer(lock.locker, amount);
        emit LiquidityUnlocked(pair, amount);
    }
    
    
    /**
     * @notice Owner: Rescue tokens accidentally sent to this contract.
     * @dev Withdraw any ERC20 tokens that were mistakenly sent to this contract address.
     * @param token The contract address of the token to rescue.
     * @param to The address to send the rescued tokens to.
     * @param amount The number of tokens to rescue.
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(0), "E64");
        require(to != address(0), "E65");
        
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
    require(contractBalance >= amount, "E66");
        
        if (liquidityLocks[token].isLocked && liquidityLocks[token].amount > 0) {
        require(contractBalance - amount >= liquidityLocks[token].amount,
            "E67");
        }
        
    require(IERC20(token).transfer(to, amount), "E61");
    }
    
    /**
     * @notice Owner: Set maximum allowed slippage for all operations
     * @dev Sets a hard cap on slippage to prevent extreme price impact
     * @param newMaxSlippage Maximum slippage in basis points (e.g., 1000 = 10%)
     */
    function setMaxAllowedSlippage(uint256 newMaxSlippage) external onlyOwner {
        require(newMaxSlippage >= MIN_SLIPPAGE_BPS, "E45");
        require(newMaxSlippage <= ABSOLUTE_MAX_SLIPPAGE, "E68");
        
        uint256 oldSlippage = maxAllowedSlippage;
        maxAllowedSlippage = newMaxSlippage;
        emit MaxSlippageUpdated(oldSlippage, newMaxSlippage);
    }

    /**
     * @notice Owner: Emergency withdraw BNB (Owner, after 30 days)
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner {
        require(block.timestamp > launchTime + 30 days, "E69");
        require(to != address(0), "E70");
        require(amount <= address(this).balance, "E71");
        
        (bool success, ) = to.call{value: amount}("");
    require(success, "E72");
    }

    /**
     * @notice Owner: Reset circuit breaker and resume auto-liquidity
     * @dev Resets slippage failure counter and resumes auto-liquidity operations
     */
    function resetCircuitBreaker() external onlyOwner {
        require(autoLiquidityPaused, "E73");
        _consecutiveSlippageFailures = 0;
        autoLiquidityPaused = false;
        emit CircuitBreakerTriggered("M02");
    }

    /**
     * @notice Owner: Configures MEV protection settings
     * @dev Sets parameters for detecting and preventing MEV attacks
     * @param enabled True to enable MEV protection
     * @param maxBlocks Maximum blocks between transactions for detection
     * @param minTime Minimum seconds between transactions
     */
    function setMevProtectionConfig(
        bool enabled,
        uint256 maxBlocks,
        uint256 minTime
    ) external onlyOwner {
    require(maxBlocks <= 10, "E74");
    require(minTime <= 300, "E75");
        
        mevProtectionEnabled = enabled;
        maxBlocksForMevProtection = maxBlocks;
        minTimeBetweenTxs = minTime;
        
        emit MevProtectionConfigured(enabled, maxBlocks, minTime);
    }

    /**
     * @notice Owner: Sets MEV protection exemption for addresses
     * @dev Allows certain addresses to bypass MEV protection
     * @param account Address to exempt or un-exempt
     * @param exempt True to exempt from MEV protection
     */
    function setMevProtectionExempt(address account, bool exempt) external onlyOwner {
        require(account != address(0), "E32");
        mevProtectionExempt[account] = exempt;
        emit MevProtectionExemptUpdated(account, exempt);
    }

    // ============================================
    // INTERNAL FUNCTIONS - Not Callable Externally
    // ============================================
    
    /**
     * @dev Creates new tokens and adds them to an account
     * @param account Address to receive newly created tokens
     * @param amount Number of tokens to create (in wei)
     */
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "E76");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    
    /**
     * @dev Destroys tokens from an account permanently
     * @param account Address to burn tokens from
     * @param amount Number of tokens to destroy (in wei)
     */
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "E77");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "E78");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }
    
    /**
     * @dev Basic transfer function without tax or fee logic
     * @param from Address sending the tokens
     * @param to Address receiving the tokens
     * @param amount Number of tokens to transfer (in wei)
     */
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "E79");
        require(to != address(0), "E80");
        
        
        uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "E83");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @dev Sets spending allowance for a spender
     * @param tokenOwner Address that owns the tokens
     * @param spender Address allowed to spend the tokens
     * @param amount Maximum tokens the spender can use
     */
    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        require(tokenOwner != address(0), "E84");
        require(spender != address(0), "E85");
        _allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }

    /**
     * @dev Public function to increase the allowance for a spender
     * This is a safer alternative to approve that mitigates the race condition
     * @param spender The address that will be allowed to spend the tokens
     * @param addedValue The number of tokens to increase the allowance by (in wei)
    */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
    uint256 currentAllowance = allowance(msg.sender, spender);
    require(currentAllowance + addedValue >= currentAllowance, "E86");
    _approve(msg.sender, spender, currentAllowance + addedValue);
    return true;
}

    /**
     * @dev Public function to decrease the allowance for a spender
     * This is a safer alternative to approve that mitigates the race condition
     * @param spender The address that will be allowed to spend the tokens
     * @param subtractedValue The number of tokens to decrease the allowance by (in wei)
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
    uint256 currentAllowance = allowance(msg.sender, spender);
    require(currentAllowance >= subtractedValue, "E87");
    _approve(msg.sender, spender, currentAllowance - subtractedValue);
    return true;
}
    
    /**
     * @dev Internal function to reduce allowance when tokens are spent
     * Updates allowance after a successful transferFrom operation
     * If allowance is set to max uint256, it won't be reduced (infinite approval)
     * @param account The address that owns the tokens
     * @param spender The address that is spending the tokens
     * @param amount The number of tokens being spent (in wei)
     * 
     * Requirements:
     * - Current allowance must be greater than or equal to `amount` (unless infinite)
     * 
     * NOTE: Does not update the allowance if it is set to type(uint256).max
     */
    function _spendAllowance(address account, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(account, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "E88");
            unchecked {
                _approve(account, spender, currentAllowance - amount);
            }
        }
    }
    
    /**
     * @dev Internal transfer function with comprehensive tax logic and security checks
     * This is the main transfer function that handles all business logic including:
     * - Pause check: Prevents transfers when contract is paused
     * - Transaction limits: Enforces max transaction and wallet limits
     * - Anti-dump protection: Prevents large sells that could crash price
     * - Anti-bot protection: Blocks bot trading during launch period
     * - Tax calculation: Applies buy/sell/transfer taxes based on transaction type
     * - Price impact check: Prevents trades that would move price too much
     * - Auto-liquidity: Automatically adds liquidity when threshold reached
     * 
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param amount The total number of tokens to transfer (tax will be deducted)
     * 
     * Tax Logic:
     * - Owner and contract transfers: No tax
     * - Tax-exempt addresses: No tax
     * - Buy from DEX: buyTaxPercent applied
     * - Sell to DEX: sellTaxPercent applied
     * - Wallet to wallet: transferTaxPercent applied
     * 
     * The tax amount is sent to the treasury address, remainder goes to recipient
     */
    function _transferWithTax(address from, address to, uint256 amount) internal nonReentrant {
        // Pause check - if pauseIncludesOwner is true, owner is also paused
        if (_paused) {
            if (pauseIncludesOwner) {
                revert("E89");
            } else {
                require(from == _owner || to == _owner, "E89");
            }
        }
    require(amount > 0, "E39");
    require(from != address(0), "E79");
    require(to != address(0), "E80");
        
        // MEV Protection - prevent sandwich attacks and front-running
        if (mevProtectionEnabled && !mevProtectionExempt[from] && !mevProtectionExempt[to]) {
            // Block number protection - prevent multiple transactions in same block
            if (lastBlockNumber[from] != 0 && (block.number - lastBlockNumber[from]) <= maxBlocksForMevProtection) {
                emit MevAttackPrevented(from, block.number, "M03");
                revert("E90");
            }
            
            // Time-based protection
            if (lastTradeTime[from] != 0 && (block.timestamp - lastTradeTime[from]) < minTimeBetweenTxs) {
                emit MevAttackPrevented(from, block.number, "M04");
                revert("E91");
            }
            
            // Update tracking for sender (both block and time)
            lastBlockNumber[from] = block.number;
            lastTradeTime[from] = block.timestamp;
            
            // For sells to DEX, also check recipient (prevent coordinated attacks)
            if (isPancakePair[to] && lastBlockNumber[to] != 0 && 
                (block.number - lastBlockNumber[to]) <= maxBlocksForMevProtection) {
                emit MevAttackPrevented(to, block.number, "M05");
                revert("E92");
            }
            
            if (isPancakePair[to]) {
                lastBlockNumber[to] = block.number;
                lastTradeTime[to] = block.timestamp;
            }
        }
        
        // Check transaction limits
        if (!taxExempt[from] && !taxExempt[to]) {
            
            // Calculate actual amount recipient will receive for wallet limit check
            if (to != address(this) && !isPancakePair[to]) {
                uint256 tax = _calculateTax(from, to, amount);
                uint256 receivedAmount = amount - tax;
                
                // Safe addition check
                uint256 newBalance = _balances[to] + receivedAmount;
                require(newBalance >= _balances[to], "E94");
            }
        }
        
        // Check wallet cooldown globally (no exemptions)
        if (walletCooldownEnabled) {
            // Check sender cooldown
            require(block.timestamp >= lastTradeTime[from] + globalCooldownSeconds, "E96");
            
            // Check recipient cooldown (prevent bypass through intermediary wallets)
            if (!isPancakePair[to] && to != address(this)) {
                require(block.timestamp >= lastTradeTime[to] + globalCooldownSeconds, "E97");
                // Only update recipient time if not already updated by MEV protection
                if (!mevProtectionEnabled || mevProtectionExempt[to]) {
                    lastTradeTime[to] = block.timestamp;
                }
            }
            
            // Only update sender time if not already updated by MEV protection
            if (!mevProtectionEnabled || mevProtectionExempt[from]) {
                lastTradeTime[from] = block.timestamp;
            }
        } else {
            // If wallet cooldown is disabled but MEV protection wasn't enabled,
            // ensure lastTradeTime is still updated for potential future MEV checks
            if (!mevProtectionEnabled) {
                lastTradeTime[from] = block.timestamp;
                if (!isPancakePair[to] && to != address(this)) {
                    lastTradeTime[to] = block.timestamp;
                }
            }
        }
        
        // Check price impact limits for sells to DEX
        if (priceImpactLimitEnabled && isPancakePair[to] && !priceImpactExempt[from] && pancakeRouter != address(0)) {
            uint256 priceImpact = _calculatePriceImpact(amount);
            require(priceImpact <= maxPriceImpactPercent, "E98");
        }
        
        // Anti-dump check for sells to DEX
        if (antiDumpEnabled && isPancakePair[to] && !taxExempt[from]) {
            uint256 maxSellAmount = (_totalSupply * maxSellPercentage) / 100;
            require(amount <= maxSellAmount, "E99");
            
            // This prevents conflicts with wallet cooldown system
            require(block.timestamp >= lastTradeTime[from] + sellCooldown, "E100");
            // Note: lastTradeTime[from] is updated later in MEV/cooldown checks
        }
        
        // Anti-bot check during launch period
        if (antiBotEnabled && block.timestamp < launchTime + antiBotDuration) {
            require(from == _owner || to == _owner || taxExempt[from] || taxExempt[to], "E101");
        }
        
        // Check if we should trigger auto-liquidity
        bool shouldSwapAndLiquify = autoLiquidityEnabled &&
            !inSwapAndLiquify &&
            from != pancakePair &&
            accumulatedLiquidityTokens >= liquidityThreshold &&
            pancakeRouter != address(0) &&
            !autoLiquidityPaused &&
            _consecutiveSlippageFailures < MAX_CONSECUTIVE_FAILURES;
        
        // Apply tax or exempt
        if (
            from == _owner ||
            to == _owner ||
            from == address(this) ||
            to == address(this) ||
            taxExempt[from] ||
            taxExempt[to] ||
            inSwapAndLiquify
        ) {
            // No tax - direct transfer
            _transfer(from, to, amount);
        } else {
            uint256 tax = _calculateTax(from, to, amount);
            
            if (tax > 0 && treasury != address(0)) {
                uint256 afterTax = amount - tax;
                
                // Split tax between treasury and liquidity if auto-liquidity enabled
                if (autoLiquidityEnabled && liquidityFeePercent > 0) {
                    uint256 liquidityPortion = (tax * liquidityFeePercent) / 100;
                    uint256 treasuryPortion = tax - liquidityPortion;
                    
                    // Transfer recipient amount (after tax deduction)
                    _transfer(from, to, afterTax);
                    
                    // Transfer liquidity portion to contract (if any)
                    if (liquidityPortion > 0) {
                        // When auto-liquidity is paused, send liquidity portion to treasury instead
                        // This prevents indefinite accumulation while circuit breaker is active
                        if (autoLiquidityPaused) {
                            _transfer(from, treasury, liquidityPortion);
                        } else {
                            _transfer(from, address(this), liquidityPortion);
                            // Safe addition
                            uint256 newAccumulated = accumulatedLiquidityTokens + liquidityPortion;
                            require(newAccumulated >= accumulatedLiquidityTokens, "E102");
                            accumulatedLiquidityTokens = newAccumulated;
                        }
                    }
                    
                    // Transfer treasury portion (if any)
                    if (treasuryPortion > 0) {
                        _transfer(from, treasury, treasuryPortion);
                    }

                    // Verify total transferred equals original amount (always true by definition)
                    assert(afterTax + liquidityPortion + treasuryPortion == amount);
                } else {
                    // No auto-liquidity: direct transfer with tax to treasury
                    _transfer(from, to, afterTax);
                    _transfer(from, treasury, tax);
                    
                    // Verify total transferred equals original amount (always true by definition)
                    assert(afterTax + tax == amount);
                }
            } else {
                // No tax applicable
                _transfer(from, to, amount);
            }
        }

        // Trigger auto-liquidity after all transfers complete (Checks-Effects-Interactions)
        if (shouldSwapAndLiquify) {
            _swapAndLiquify(accumulatedLiquidityTokens);
        }
    }

    /**
     * @dev Calculate tax for a transfer
     */
    function _calculateTax(address from, address to, uint256 amount) private view returns (uint256) {
        uint256 taxBps = 0;
        
        // Use basis points system for precise tax calculation
        if (isPancakePair[from] && !isPancakePair[to]) {
            taxBps = buyTaxBps;
        } else if (!isPancakePair[from] && isPancakePair[to]) {
            taxBps = sellTaxBps;
        } else if (!isPancakePair[from] && !isPancakePair[to]) {
            taxBps = transferTaxBps;
        }
        
        if (taxBps == 0) return 0;
        
        // Safe multiplication and division with basis points (1 bp = 0.01%)
        // tax = (amount * taxBps) / 10000
        // Check for overflow BEFORE calculation to prevent wrap-around
        if (amount > type(uint256).max / taxBps) return 0; // Overflow protection
        
        uint256 tax = (amount * taxBps) / BASIS_POINTS;
        
        // Note: tax <= amount is guaranteed by the overflow check above
        // since taxBps <= 2500 (max 25%) and BASIS_POINTS = 10000
        // If amount * taxBps doesn't overflow, then tax = (amount * taxBps) / 10000 <= amount
        
        return tax;
    }
    
    function _swapAndLiquify(uint256 tokensToLiquify) private lockTheSwap {
        require(tokensToLiquify > 0, "E53");
        require(pancakeRouter != address(0), "E52");
        require(_validatedRouters[pancakeRouter], "E104");
        
        // Validate slippage is within safe bounds
        uint256 effectiveSlippage = calculateDynamicSlippage(tokensToLiquify / 2);
    require(effectiveSlippage <= maxAllowedSlippage, "E105");
        
        // Split tokens: half for swap, half for liquidity
        uint256 half = tokensToLiquify / 2;
        uint256 otherHalf = tokensToLiquify - half;

        // Capture initial BNB balance
        uint256 initialBalance = address(this).balance;

        // Perform swap with retry mechanism
        bool swapSuccess = false;
        uint256 attempts = 0;
        uint256 maxAttempts = 3;
        uint256 minGasPerAttempt = 300000; // Increased gas requirement

        while (attempts < maxAttempts && gasleft() > minGasPerAttempt) {
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = IPancakeRouter(pancakeRouter).WETH();
            
            // Approve exact amount for swap
            _approve(address(this), pancakeRouter, half);
            
            try IPancakeRouter(pancakeRouter).getAmountsOut(half, path) returns (uint[] memory amounts) {
                if (amounts.length < 2 || amounts[1] == 0) {
                    // Reset approval on failure to prevent leftover approvals
                    _approve(address(this), pancakeRouter, 0);
                    emit SwapFailed(half, "M06");
                    break;
                }
                
                uint256 minBnbAmount = (amounts[1] * (BASIS_POINTS - effectiveSlippage)) / BASIS_POINTS;

                try IPancakeRouter(pancakeRouter).swapExactTokensForETHSupportingFeeOnTransferTokens(
                    half,
                    minBnbAmount,
                    path,
                    address(this),
                    block.timestamp + 300
                ) {
                    // Reset approval after successful swap to prevent residual approvals
                    _approve(address(this), pancakeRouter, 0);
                    emit SwapAttempted(half, effectiveSlippage, true);
                    swapSuccess = true;
                    _consecutiveSlippageFailures = 0; // Reset on success
                    break;
                } catch Error(string memory reason) {
                    attempts++;
                    if (attempts >= maxAttempts) {
                        // Reset approval on final failure
                        _approve(address(this), pancakeRouter, 0);
                        emit SwapFailed(half, reason);
                        _consecutiveSlippageFailures++;
                    } else {
                        // Conservative retry slippage increase
                        uint256 retrySlippage = effectiveSlippage + 50; // +0.5%
                        effectiveSlippage = retrySlippage > maxAllowedSlippage ? maxAllowedSlippage : retrySlippage;
                    }
                } catch {
                    attempts++;
                    if (attempts >= maxAttempts) {
                        // Reset approval on final failure
                        _approve(address(this), pancakeRouter, 0);
                        emit SwapFailed(half, "M07");
                        _consecutiveSlippageFailures++;
                    }
                }
            } catch {
                // Reset approval on failure to prevent leftover approvals
                _approve(address(this), pancakeRouter, 0);
                emit SwapFailed(half, "M08");
                _consecutiveSlippageFailures++;
                break;
            }
        }

        // Circuit breaker - pause auto-liquidity after consecutive failures
        if (_consecutiveSlippageFailures >= MAX_CONSECUTIVE_FAILURES) {
            autoLiquidityPaused = true;
            // Reset accumulated tokens to prevent indefinite growth while paused
            // This prevents contract from becoming unusable due to excessive accumulation
            accumulatedLiquidityTokens = 0;
            emit CircuitBreakerTriggered("M09");
        }

        uint256 bnbReceived = address(this).balance - initialBalance;

        if (swapSuccess && bnbReceived > 0) {
            // Approve exact amount for liquidity addition
            _approve(address(this), pancakeRouter, otherHalf);
            
            uint256 minTokenAmount = (otherHalf * (BASIS_POINTS - effectiveSlippage)) / BASIS_POINTS;
            uint256 minBnbAmount = (bnbReceived * (BASIS_POINTS - effectiveSlippage)) / BASIS_POINTS;

            try IPancakeRouter(pancakeRouter).addLiquidityETH{value: bnbReceived}(
                address(this),
                otherHalf,
                minTokenAmount,
                minBnbAmount,
                _owner,
                block.timestamp + 300
            ) returns (uint amountToken, uint amountETH, uint liquidity) {
                // Reset approval after successful liquidity addition
                _approve(address(this), pancakeRouter, 0);
                accumulatedLiquidityTokens = 0;
                lastLiquidityAddTime = block.timestamp;
                
                // Safe addition
                uint256 newTotal = totalLiquidityAdded + tokensToLiquify;
                require(newTotal >= totalLiquidityAdded, "E106");
                totalLiquidityAdded = newTotal;
                
                emit LiquidityAdded(amountToken, amountETH, liquidity);
            } catch Error(string memory reason) {
                // Reset approval on failure to prevent leftover approvals
                _approve(address(this), pancakeRouter, 0);
                emit LiquidityOperationFailed("M10", reason);
                _consecutiveSlippageFailures++;
            } catch {
                // Reset approval on failure to prevent leftover approvals
                _approve(address(this), pancakeRouter, 0);
                emit LiquidityOperationFailed("M10", "M11");
                _consecutiveSlippageFailures++;
            }
        } else {
            // Reset on swap failure to prevent stuck state
            accumulatedLiquidityTokens = 0;
            emit LiquidityOperationFailed("M12", "M12");
        }
    }
    
    function calculateDynamicSlippage(uint256 amount) internal view returns (uint256) {
        if (amount == 0) return maxAllowedSlippage;
        
        uint256 calculatedSlippage;
        if (amount >= DYNAMIC_SLIPPAGE_THRESHOLD) {
            calculatedSlippage = HIGH_VOLUME_SLIPPAGE;  // 200 (2%)
        } else {
            calculatedSlippage = LOW_VOLUME_SLIPPAGE;   // 500 (5%)
        }
        
        // Always respect maximum allowed slippage
        return calculatedSlippage > maxAllowedSlippage ? maxAllowedSlippage : calculatedSlippage;
    }
    
    function _calculatePriceImpact(uint256 amount) internal view returns (uint256 impact) {
        if (pancakeRouter == address(0) || pancakePair == address(0) || amount == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IPancakeRouter(pancakeRouter).WETH();

        // Use smaller reference amount for spot price (prevent overflow)
        uint256 referenceAmount = 1 * 10**_decimals;
        
        // Critical safety check: Ensure referenceAmount is never zero
        // This protects against edge cases with decimals configuration
        if (referenceAmount == 0) return maxPriceImpactPercent;
        
        // Additional safety check for extremely large amounts
        if (amount > _totalSupply / 10) return maxPriceImpactPercent; // Cap at 10% of supply
        
        try IPancakeRouter(pancakeRouter).getAmountsOut(referenceAmount, path) returns (uint[] memory refAmounts) {
            if (refAmounts.length < 2 || refAmounts[1] == 0) return maxPriceImpactPercent;
            
            try IPancakeRouter(pancakeRouter).getAmountsOut(amount, path) returns (uint[] memory tradeAmounts) {
                if (tradeAmounts.length < 2 || tradeAmounts[1] == 0) return maxPriceImpactPercent;
                
                // Calculate price impact with enhanced overflow protection
                
                // Check if multiplication will overflow BEFORE performing it
                if (refAmounts[1] > type(uint256).max / amount) return maxPriceImpactPercent;
                
                uint256 spotPriceNumerator = refAmounts[1] * amount;
                uint256 spotPriceDenominator = referenceAmount;
                uint256 actualPrice = tradeAmounts[1];
                
                // Verify multiplication was safe
                if (spotPriceNumerator / amount != refAmounts[1]) return maxPriceImpactPercent;
                
                // Safe division check
                if (spotPriceDenominator == 0) return maxPriceImpactPercent;
                uint256 expectedOutput = spotPriceNumerator / spotPriceDenominator;
                
                // Check for underflow and handle edge cases
                if (actualPrice >= expectedOutput) return 0; // No negative impact or rounding error
                
                uint256 priceDiff = expectedOutput - actualPrice;
                
                // Enhanced overflow protection for basis points calculation
                if (expectedOutput == 0) return maxPriceImpactPercent;
                if (priceDiff > expectedOutput) return maxPriceImpactPercent; // Sanity check
                if (priceDiff > type(uint256).max / BASIS_POINTS) return maxPriceImpactPercent;
                
                impact = (priceDiff * BASIS_POINTS) / expectedOutput;
                
                // Final bounds checking
                if (impact > BASIS_POINTS) impact = BASIS_POINTS; // Cap at 100%
                if (impact > maxPriceImpactPercent) impact = maxPriceImpactPercent;
                
            } catch {
                return maxPriceImpactPercent;
            }
        } catch {
            return maxPriceImpactPercent;
        }
        
        return impact;
    }


    
    /**
     * @notice Get auto-liquidity configuration and statistics
     * @return enabled Whether auto-liquidity is active
     * @return feePercent Percentage of tax going to liquidity
     * @return threshold Minimum tokens needed to trigger auto-liquidity
     * @return accumulated Current tokens accumulated for liquidity
     * @return totalAdded Total tokens converted to liquidity since deployment
     * @return lastAddTime Last time liquidity was added (Unix timestamp)
     * @return slippageBps Current slippage tolerance in basis points
     */
    function getAutoLiquidityInfo() public view returns (
        bool enabled,
        uint256 feePercent,
        uint256 threshold,
        uint256 accumulated,
        uint256 totalAdded,
        uint256 lastAddTime,
        uint256 slippageBps
    ) {
        return (
            autoLiquidityEnabled,
            liquidityFeePercent,
            liquidityThreshold,
            accumulatedLiquidityTokens,
            totalLiquidityAdded,
            lastLiquidityAddTime,
            autoLiquiditySlippageBps
        );
    }
    
   

    /**
     * @dev Internal function to check if an address is a contract
     * @param account The address to check
     * @return True if the address is a contract, false if it's an EOA
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // Required to receive BNB from PancakeSwap
    receive() external payable {
        // Emit event to track source for monitoring
        emit BNBReceived(msg.sender, msg.value);
    
    }
}
