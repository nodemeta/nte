// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Node Meta Energy (NTE) - Advanced BEP20 Token
 * @custom:security-contact security@node-meta.com
 */

/*
 * ═══════════════════════════════════════════════════════════════════════════
 * ERROR CODES - Making Sense of Reverts
 * ═══════════════════════════════════════════════════════════════════════════
 * We use descriptive prefixes so you know exactly why a transaction failed.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ PERMISSIONS & OWNERSHIP [AUTH_*]                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 * AUTH_OWNER       Only the owner can do this   AUTH_ZERO_OWNER    Owner can't be zero address
 * AUTH_LOCKED      Ownership lock active (30d)  AUTH_SAME_OWNER    Already the current owner
 * AUTH_INVALID     Invalid auth signer key       AUTH_ALREADY_SET   Signer is already authorized
 * AUTH_NOT_SET     Signer isn't authorized       AUTH_ZERO_ADDR     Signer can't be zero address
 * AUTH_NOT_PENDING_OWNER  Not the pending owner  AUTH_NO_PENDING_TRANSFER  No pending ownership transfer
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ SYSTEM & SECURITY [SYS_*, SEC_*]                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 * SYS_DISABLED     Transfers are disabled        SEC_REENTRY        No reentrancy allowed
 * SEC_BOT_ACTIVE   Anti-bot period active
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ DEX & LIQUIDITY [DEX_*, LIQ_*]                                          │
 * └─────────────────────────────────────────────────────────────────────────┘
 * DEX_ROUTER       Router isn't a contract       DEX_PAIR_ZERO      Pair address is zero
 * DEX_FACTORY_ZERO Factory address is zero       DEX_PAIR_FAIL      Failed to set up pair
 * DEX_FACTORY      Factory isn't a contract      DEX_PAIR_CHECK     Pair validation failed
 * DEX_WETH_ZERO    WETH address is zero          DEX_WETH_CALL      WETH call failed
 * DEX_WETH         WETH isn't a contract         DEX_FACTORY_CALL   Factory call failed
 * DEX_PAIR_NOT_CONTRACT Pair isn't a contract
 * LIQ_COLLECTOR_HAS_BALANCE Old collector has pending tokens
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ THE TAX MAN [TAX_*]                                                     │
 * └─────────────────────────────────────────────────────────────────────────┘
 * TAX_BUY_HIGH     Buy tax is over 25%           TAX_BUY_DELTA      Buy tax changed too much
 * TAX_SELL_HIGH    Sell tax is over 25%          TAX_SELL_DELTA     Sell tax changed too much
 * TAX_XFER_HIGH    Transfer tax is over 25%      TAX_XFER_DELTA     Transfer tax changed too much
 * TAX_TOTAL_HIGH   Total tax is over 50%         TAX_COOLDOWN       Wait before changing taxes
 * TAX_TREASURY_ZERO Treasury can't be zero       TAX_TREASURY_SAME  Already using this treasury
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ BLACKLISTS & WHITELISTS [BL_*, WL_*]                                    │
 * └─────────────────────────────────────────────────────────────────────────┘
 * BL_OWNER         Can't blacklist the owner     BL_SENDER          Sender is blacklisted
 * BL_CONTRACT      Can't blacklist this contract BL_RECIPIENT       Recipient is blacklisted
 * BL_EXPIRY_INVALID Invalid expiry timestamp     WL_EXPIRY_INVALID  Invalid expiry timestamp
 * WL_REQUIRED      You need to be whitelisted
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ TRANSACTION CHECKS [TXN_*, ADDR_*]                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * TXN_AMOUNT_ZERO  Need to send more than 0      TXN_EXCEEDS_BAL    Not enough tokens
 * ADDR_FROM_ZERO   Sending from zero address     TXN_OVERFLOW       Math overflow detected
 * ADDR_TO_ZERO     Sending to zero address       TXN_SUPPLY_ZERO    Initial supply can't be 0
 * TXN_REPLAY       This transaction was used     SIG_EXPIRED        Signature past deadline
 * TXN_TAX_MISMATCH Internal tax math error
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ APPROVALS [APRV_*]                                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * APRV_FROM_ZERO   Approving from zero address   APRV_UNDERFLOW     Allowance below zero
 * APRV_TO_ZERO     Approving to zero address     APRV_INSUFFICIENT  Not enough allowance
 * APRV_OVERFLOW    Allowance overflow
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ MINTING & BURNING [MINT_*, BURN_*]                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * MINT_TO_ZERO     Can't mint to zero address    BURN_FROM_ZERO     Can't burn from zero
 * BURN_EXCEEDS     Burning more than you have
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ SHIELD PROTECTION [MEV_*]                                               │
 * └─────────────────────────────────────────────────────────────────────────┘
 * MEV_BLOCKS_HIGH  Block limit set too high      MEV_TIME_HIGH      Time window set too high
 * MEV_VELOCITY     Too many trades in window     MEV_TOO_FAST       Wait a bit between trades
 * MEV_CONFIG_INVALID Config needs at least one param set
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ TIMERS & LIMITS [CD_*, LIMIT_*]                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 * CD_TOO_HIGH      Cooldown is over 1 day        CD_SELL            Sell cooldown active
 * CD_SENDER        Sender is on cooldown         CD_RECIPIENT       Recipient is on cooldown
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ STABILITY & ANTI-DUMP [DUMP_*, PRICE_*]                                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 * DUMP_PERCENT     Percentage must be 1-100      DUMP_EXCEEDS       Selling too much at once
 * PRICE_MIN_IMPACT Min impact is 0.1%            PRICE_TOO_HIGH     Price impact is too big
 * PRICE_INVALID    Impact must be 0.1% to 100%
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ CATEGORIES & STRINGS [CAT_*, STR_*]                                     │
 * └─────────────────────────────────────────────────────────────────────────┘
 * CAT_INVALID      This category doesn't exist   CAT_DISABLED       Category is turned off
 * STR_TOO_LONG       String exceeds max length
 * STR_EMPTY        String cannot be empty
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ EMERGENCY RESCUE [EMG_*]                                                │
 * └─────────────────────────────────────────────────────────────────────────┘
 * EMG_TRANSFER_FAIL Token transfer failed         EMG_INVALID_RECIP  Recipient is invalid
 * EMG_INVALID_TOKEN Token address is invalid      EMG_INSUF_BAL_BNB  Not enough BNB
 * EMG_ZERO_RECIP   Recipient is zero address      EMG_BNB_FAIL       BNB transfer failed
 * EMG_INSUF_BAL    Not enough balance            EMG_WAIT_30D       Wait 30 days after launch
 * EMG_WAIT_1Y     Wait 1 year after launch
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ VELOCITY LIMITS [VEL_*]                                                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 * VEL_CONFIG_INVALID Invalid velocity config     VEL_LIMIT_HIGH     Velocity limit too high
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ GENERAL CHECKS [ADDR_*]                                                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 * ADDR_INVALID     Address is invalid or zero    ADDR_ZERO          Zero address not allowed
 * ADDR_NOT_CONTRACT Address isn't a contract
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ STAKING [STAKING_*]                                                     │
 * └─────────────────────────────────────────────────────────────────────────┘
 * STAKING_NOT_CONTRACT Staking address isn't a contract
 * STAKING_ACTIVE_LOCKS Cannot change staking contract with active locks
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * EVENT MESSAGE CODES
 * ═══════════════════════════════════════════════════════════════════════════
 * TREASURY_UPDATED Treasury address updated
 * MEV_BLOCK        Block interval too short
 * MEV_TIME         Time interval too short
 */

/// @title PancakeSwap Router Interface
/// @notice Minimal interface used for price quotes and pair routing
interface IPancakeRouter {
    /// @notice Returns the PancakeSwap factory address
    function factory() external pure returns (address);
    /// @notice Returns the wrapped native token (WETH) address  
    function WETH() external pure returns (address);
    /// @notice Returns output amounts for a given input amount and swap path
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

/// @title PancakeSwap Pair Interface
interface IPancakePair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title PancakeSwap Factory Interface
/// @notice Minimal factory interface used for pair creation and lookup  
interface IPancakeFactory {
    /// @notice Creates a new pair for two tokens
    function createPair(address tokenA, address tokenB) external returns (address pair);
    /// @notice Returns the pair address for two tokens, or zero if none
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @title Standard ERC20 Interface
/// @notice Core ERC20 interface with an extra categorized transfer event
interface IERC20 {
    /**
     * @notice Returns the total token supply.
     * @return The total supply of tokens.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the account balance of another account with address `account`.
     * @param account The address of the account to query.
     * @return The balance of the account.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Transfers `amount` tokens to address `to`.
     * @param to The address of the recipient.
     * @param amount The amount of tokens to transfer.
     * @return True if the transfer succeeds.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @notice Returns the amount which `spender` is still allowed to withdraw from `owner`.
     * @param owner The address of the token owner.
     * @param spender The address of the authorized spender.
     * @return The remaining allowance.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @notice Allows `spender` to withdraw from your account multiple times, up to the `amount` amount.
     * @param spender The address of the authorized spender.
     * @param amount The max amount they can spend.
     * @return True if the approval succeeds.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Transfers `amount` tokens from address `from` to address `to`.
     * @param from The address of the sender.
     * @param to The address of the recipient.
     * @param amount The amount of tokens to transfer.
     * @return True if the transfer succeeds.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @notice Emitted when the allowance of a `spender` for an `owner` is set.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Emitted when a transfer is tagged with a payment category.
     * @param from The sender of the tokens.
     * @param to The recipient of the tokens.
     * @param value The amount of tokens moved.
     * @param category The ID of the payment category.
     * @param referenceId External reference ID for tracking.
     * @param memo Optional note about the transfer.
     */
    event TransactionProcessed(address indexed from, address indexed to, uint256 value, uint8 category, string referenceId, string memo);
}

/**
 * @title Node Meta Energy (NTE) - Advanced BEP20 Token Implementation
 * @author Node Meta Team
 * @notice Main token contract implementing BEP20/ERC20 with advanced trading protections and tax system
 * @dev This contract implements a comprehensive token ecosystem with the following features:
 *      - Tax system (buy/sell/transfer taxes with configurable rates)
 *      - Auto-liquidity management (automated LP token creation)
 *      - MEV/Bot protection (multi-layer defense against malicious trading)
 *      - Anti-dump mechanisms (sell limits and cooldowns)
 *      - Velocity limits (transaction frequency controls)
 *      - Categorized transactions (off-chain signed payments with categories)
 *      - Staking integration (token locking for staking rewards)
 *      - Whitelist/Blacklist system (access control)
 *      - Two-step ownership transfer (safe ownership changes)
 *      - Emergency functions (safety mechanisms with time locks)
 * 
 * @custom:security-features
 *      - Reentrancy guards on critical functions
 *      - Overflow protection with Solidity 0.8.28
 *      - Multi-layer bot protection (anti-bot, MEV, velocity)
 *      - Time-locked emergency functions (30 days for BNB, 1 year for staking)
 *      - Signature replay protection (nonces and deadline validation)
 * 
 * @custom:tax-system
 *      - Buy tax: 0-25% (default 2%)
 *      - Sell tax: 0-25% (default 2%)
 *      - Transfer tax: 0-25% (default 3%)
 *      - Tax changes: 24-hour cooldown, max 2.5% change per update
 *      - Auto-liquidity: Route tax percentage to liquidity manager
 * 
 * @custom:deployment
 *      Initial supply is minted to initialOwner
 *      PancakeSwap pair auto-initialized if router provided
 *      Default taxes set at deployment (can be adjusted later)
 * 
 * @custom:gas-optimization
 *      - Circular buffer for velocity tracking (constant 10 slots)
 *      - Event-based transaction history (no storage arrays)
 *      - Unchecked math where overflow impossible
 *      - Custom errors instead of require strings
 */
contract NTE is IERC20 {
    
    // ===================================================
    // THE BASICS - Balances, Ownership, and State
    // ===================================================
    
    /// @notice Keeps track of how many tokens everyone has
    mapping(address => uint256) private _balances;
    /// @notice Who is allowed to spend someone else's tokens
    mapping(address => mapping(address => uint256)) private _allowances;
    /// @notice Total amount of NTE tokens in existence
    uint256 private _totalSupply;
    
    /// @notice The current captain of the contract
    address private _owner;
    
    /// @notice The pending owner waiting to accept ownership
    address private _pendingOwner;
    
    /// @notice A master switch to stop all transfers if something goes wrong
    bool private _paused;
    
    /// @notice Wallets authorized to sign off-chain instructions (apps, websites, services)
    mapping(address => bool) public isAuthSigner;
    
    /// @notice The wallet where all collected taxes are sent
    address private treasury;
    
    /// @notice Tax taken when buying (in basis points: 100 = 1%)
    uint256 private buyTaxBps;
    /// @notice Tax taken when selling
    uint256 private sellTaxBps;
    /// @notice Tax taken for standard wallet-to-wallet transfers
    uint256 private transferTaxBps;
    
    /// @notice Whether a portion of tax is routed to a liquidity manager
    bool public autoLiquidityEnabled;
    /// @notice Percentage of collected tax sent to the liquidity manager (in basis points)
    uint256 public autoLiquidityBps;
    /// @notice Contract that receives liquidity tax and manages swap+LP logic
    address public liquidityCollector;
    
    /// @notice The PancakeSwap router we talk to
    address public pancakeRouter;
    /// @notice Our main trading pool (NTE/WETH)
    address public pancakePair;
    /// @notice A list of addresses we treat as DEX pools
    mapping(address => bool) public isPancakePair;
    
    /// @notice Counter for all tokens ever sent to the burn address
    uint256 public totalBurned;
    
    /// @notice Whether our anti-bot shields are currently up
    bool private constant antiBotEnabled = true;
    /// @notice When the contract was first deployed
    uint256 public immutable launchTime;
    /// @notice How long the anti-bot protection lasts after launch
    uint256 private constant antiBotDuration = 3900;
    
    // ===================================================
    // SMART CATEGORIES - Organized Payments
    // ===================================================
    
    /// @notice How many trades happened in each category
    mapping(uint8 => uint256) public categoryTransactionCount;
    /// @notice Total volume of tokens moved per category
    mapping(uint8 => uint256) public categoryTotalVolume;
    /// @notice Your personal trade count per category
    mapping(address => mapping(uint8 => uint256)) public userCategoryCount;
    /// @notice Your personal volume per category
    mapping(address => mapping(uint8 => uint256)) public userCategoryVolume;
    
    /// @notice Whether a specific category is active right now
    mapping(uint8 => bool) public categoryEnabled;

    /**
     * @notice A personal "counter" for your categorized trades to prevent double-spending.
     */
    mapping(address => uint256) public userCategorizedNonce;
    
    /// @notice The names for our payment categories (e.g., "Charity", "Business")
    mapping(uint8 => string) public categoryNames;
    /// @notice How many categories we've created so far
    uint8 public totalCategories;

    /// @notice Emitted when we add a new authorized signer
    event AuthSignerAdded(address indexed authAddress);
    
    /// @notice Emitted when we remove an authorized signer
    event AuthSignerRemoved(address indexed authAddress);
    
    /// @notice What we call the token
    string private _name;
    /// @notice The 3-letter ticker
    string private _symbol;
    /// @notice How many decimal places (standard is 18)
    uint8 private constant _decimals = 18;
    /// @notice Link to our official logo
    string private constant _tokenLogo = "https://node-meta.com/logo/node-meta.png";
    /// @notice A quick tagline for the project
    string private constant _description = "Node Meta Energy (NTE) - Revolutionary Blockchain Technology";
    /// @notice Where you can find us online
    string private constant _website = "https://node-meta.com";
    
    /// @notice Whether we're stopping big whales from dumping
    bool public antiDumpEnabled;
    /// @notice The biggest slice of the pie you can sell at once
    uint256 public maxSellPercentage;
    /// @notice How long you have to wait between large sells
    uint256 public sellCooldown;
    
    /// @notice People on this list don't pay any taxes
    mapping(address => bool) public taxExempt;
    /// @notice Helper contracts allowed to bypass trading protections for self-owned transfers
    mapping(address => bool) public helperBypass;
    
    /// @notice People on this list are blocked from trading
    mapping(address => bool) public isBlacklisted;
    /// @notice When a temporary blacklist ends (0 means forever)
    mapping(address => uint256) public blacklistExpiry;
    
    /// @notice Whether we're in "VIP-only" mode (whitelisted only)
    bool public whitelistEnabled;
    /// @notice People allowed to trade when VIP-only mode is on
    mapping(address => bool) public isWhitelisted;
    /// @notice When someone's whitelist access expires
    mapping(address => uint256) public whitelistExpiry;
    
    /// @notice Whether we're blocking trades that move the price too much
    bool public priceImpactLimitEnabled;
    /// @notice Maximum price movement allowed in a single trade
    uint256 public maxPriceImpactPercent;
    /// @notice People who are allowed to move the price as much as they want
    mapping(address => bool) internal priceImpactExempt;
    
    /// @notice Whether we're forcing a wait time between every trade
    bool public walletCooldownEnabled;
    /// @notice The mandatory wait time between trades (in seconds)
    uint256 public globalCooldownSeconds;
    /// @notice When a wallet last made a trade
    mapping(address => uint256) internal lastTradeTime;
    
    /// @notice Internal guard to prevent "re-entry" attacks
    bool private _entered;

    /// @notice We lock the Chain ID here to prevent signature theft on other chains
    uint256 private immutable _deploymentChainId;

    /// @notice Maximum allowed cooldown (1 full day)
    uint256 private constant MAX_COOLDOWN = 86400;
    /// @notice Our math denominator (10000 = 100%)
    uint256 private constant BASIS_POINTS = 10000;
    /// @notice Safety cap for the length of text strings
    uint256 private constant MAX_STRING_LENGTH = 256;
    /// @notice Maximum wait time for anti-dump rules (30 days)
    uint256 private constant MAX_ANTI_DUMP_COOLDOWN = 30 days;
    /// @notice Ownership lock period before renouncement or emergency actions (30 days)
    uint256 private constant OWNERSHIP_LOCK_PERIOD = 30 days;
    /// @notice Maximum tax rate for any tax category (25%)
    uint256 private constant MAX_TAX_LIMIT = 2500;
    /// @notice Maximum combined total of all tax rates (50%)
    uint256 private constant MAX_TOTAL_TAX_LIMIT = 5000;
    /// @notice Maximum allowed change in tax rate per update (2.5%)
    uint256 private constant MAX_TAX_CHANGE_DELTA = 250;
    /// @notice Maximum anti-dump percentage (100%)
    uint256 private constant MAX_ANTI_DUMP_PERCENT = 10000;
    /// @notice Minimum price impact threshold in basis points (0.1%)
    uint256 private constant MIN_PRICE_IMPACT_BPS = 10;
    /// @notice Maximum MEV protection block difference
    uint256 private constant MAX_MEV_BLOCKS = 10;
    /// @notice Maximum MEV protection time threshold (5 minutes)
    uint256 private constant MAX_MEV_MIN_TIME = 300;
    /// @notice Minimum hold time before sell to prevent rapid buy-sell (60 seconds)
    uint256 private constant MIN_HOLD_BEFORE_SELL = 60;

    
    /// @notice The last time we updated the tax rates
    uint256 private _lastTaxChangeTime;
    /// @notice Safety rule: taxes can only be changed once every 24 hours
    uint256 private constant TAX_CHANGE_COOLDOWN = 1 days;
    
    /// @notice Whether even the owner is blocked when the contract is paused
    bool public pauseIncludesOwner;
    
    
    /// @notice Whether our "MEV Shield" is active against bots
    bool private mevProtectionEnabled;
    /// @notice How many blocks apart trades must be
    uint256 private maxBlocksForMevProtection;
    /// @notice Keeping track of which block a wallet last traded in
    mapping(address => uint256) internal lastBlockNumber;
    /// @notice People who are allowed to bypass MEV checks
    mapping(address => bool) internal mevProtectionExempt;
    /// @notice Minimum time (in seconds) between trades
    uint256 private minTimeBetweenTxs;
    
    // ===================================================
    // VELOCITY CONTROL - Slowing Down the Pace
    // ===================================================
    
    /// @notice Whether we're limiting how many trades you can do in a row
    bool private velocityLimitEnabled;
    /// @notice The "speed limit" for transactions
    uint256 private maxTxPerWindow;
    /// @notice The time window (in seconds) for the speed limit
    uint256 private velocityTimeWindow;
    
    /// @notice Max number of trades we track for the speed limit
    uint256 private constant MAX_VELOCITY_BUFFER = 10;
    /// @notice Internal counter for your "speed limit" tracker
    mapping(address => uint256) private userVelocityIndex;
    /// @notice A list of your most recent trade timestamps
    /// @dev We keep it at 10 to keep gas costs low.
    mapping(address => uint256[MAX_VELOCITY_BUFFER]) private userVelocityBuffer;

    /**
     * @notice People who don't have a "speed limit" on their trades.
     */
    mapping(address => bool) internal velocityLimitExempt;

    /// @notice The staking contract allowed to lock balances
    address public stakingContract;
    /// @notice Whether helper-bypass transfers must satisfy whitelist checks when whitelist mode is enabled
    bool public enforceWhitelistOnHelper = true;
    /// @notice Amount of tokens locked in staking per user
    mapping(address => uint256) public lockedForStaking;
    /// @notice Aggregate amount currently locked for staking across all users
    uint256 public totalLockedForStaking;

    // ===================================================
    // EVENTS
    // ===================================================
    
    /// @notice Emitted when contract ownership changes
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when ownership transfer is initiated
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when contract is paused
    event Paused(address account);
    /// @notice Emitted when contract is unpaused
    event Unpaused(address account);
    /// @notice Emitted when tax exemption status is updated
    event TaxExemptUpdated(address account, bool exempt);
    /// @notice Emitted when blacklist status for an address changes
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    /// @notice Emitted when whitelist status for an address changes
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    /// @notice Emitted when whitelist-only trading mode is toggled
    event WhitelistModeUpdated(bool enabled); 
    /// @notice Emitted when token name and symbol change
    event NameSymbolUpdated(string newName, string newSymbol);
    /// @notice Emitted when anti-dump configuration changes
    event AntiDumpConfigUpdated(bool enabled, uint256 maxPercentage, uint256 cooldown);
    /// @notice Emitted when price impact limit settings change
    event PriceImpactLimitConfigUpdated(bool enabled, uint256 maxImpact);
    /// @notice Emitted when price impact exemption for an address changes
    event PriceImpactExemptUpdated(address indexed account, bool exempt);
    /// @notice Emitted when wallet cooldown settings change
    event WalletCooldownConfigUpdated(bool enabled, uint256 cooldownSeconds);
    /// @notice Emitted when BNB is received by the contract
    event BNBReceived(address indexed sender, uint256 amount);
    
    /// @notice Emitted when the treasury address is updated
    event TreasuryUpdated(address indexed newTreasury);
    
    /// @notice Emitted when tax rates are updated
    event TaxRatesUpdated(uint256 newBuyTaxBps, uint256 newSellTaxBps, uint256 newTransferTaxBps);
    /// @notice Emitted when tax is routed to the treasury
    event TaxRouted(address indexed from, address indexed treasury, uint256 amount);
    /// @notice Emitted when tax is routed to the liquidity manager
    event LiquidityRouted(address indexed from, address indexed liquidityCollector, uint256 amount);
    /// @notice Emitted when auto-liquidity configuration is updated
    event AutoLiquidityConfigUpdated(bool enabled, uint256 percentageBps, address liquidityCollector);
    
    /// @notice Emitted when protection settings change
    event MevProtectionConfigured(bool enabled, uint256 maxBlocks, uint256 minTime);
    /// @notice Emitted specifically when MEV protection is toggled on/off
    event MevProtectionToggled(bool enabled);
    /// @notice Emitted when a transaction is blocked by protection logic
    event MevAttackPrevented(address indexed account, uint256 blockNumber, string reason);
    /// @notice Emitted when protection exemption for an address changes
    event MevProtectionExemptUpdated(address indexed account, bool exempt);
    
    /// @notice Emitted when a payment category is enabled or disabled
    event CategoryStatusUpdated(uint8 indexed category, bool enabled);
    /// @notice Emitted when category statistics are updated
    event CategoryStatsUpdated(uint8 indexed category, uint256 txCount, uint256 totalVolume);
    /// @notice Emitted when a new payment category is added
    event CategoryAdded(uint8 indexed categoryId, string name);
    /// @notice Emitted when an existing payment category is updated
    event CategoryUpdated(uint8 indexed categoryId, string name);
    
    /// @notice Emitted when velocity protection settings change
    event VelocityLimitConfigured(bool enabled, uint256 maxTxPerWindow, uint256 timeWindow);
    /// @notice Emitted when a transaction hits the velocity protection limit
    event VelocityLimitTriggered(address indexed account, uint256 txCount, uint256 timeWindow);
    /// @notice Emitted when velocity protection exemption for an address changes
    event VelocityLimitExemptUpdated(address indexed account, bool exempt);
    /// @notice Emitted when helper bypass status is changed
    event HelperBypassUpdated(address indexed helper, bool enabled);
    /// @notice Emitted when blacklist expiry is set or cleared
    event BlacklistExpirySet(address indexed account, uint256 expiryTime);
    /// @notice Emitted when whitelist expiry is set or cleared
    event WhitelistExpirySet(address indexed account, uint256 expiryTime);
    /// @notice Emitted when a DEX pair status is added or removed
    event DexPairUpdated(address indexed pair, bool isPair);
    /// @notice Emitted when emergency token withdrawal occurs
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when emergency BNB withdrawal occurs
    event EmergencyBNBWithdraw(address indexed to, uint256 amount);
    /// @notice Emitted when the staking contract address is updated
    event StakingContractUpdated(address indexed newStakingContract);
    /// @notice Emitted when helper whitelist enforcement is toggled
    event HelperWhitelistEnforcementUpdated(bool enabled);
    /// @notice Emitted when the PancakeSwap router is updated
    event PancakeRouterUpdated(address indexed newRouter);
    /// @notice Emitted when the primary PancakeSwap pair is updated
    event PancakePairUpdated(address indexed newPair);
    /// @notice Emitted when tokens are locked for staking
    event TokensLockedForStaking(address indexed user, uint256 amount);
    /// @notice Emitted when tokens are unlocked from staking
    event TokensUnlockedFromStaking(address indexed user, uint256 amount);

    // ===================================================
    // MODIFIERS
    // ===================================================
    
    /// @notice Restricts function access to the contract owner
    modifier onlyOwner() {
        if (msg.sender != _owner) revert AUTH_OWNER();
        _;
    }
    
    /// @notice Simple reentrancy guard modifier
    modifier nonReentrant() {
        if (_entered) revert SEC_REENTRY();
        _entered = true;
        _;
        _entered = false;
    }
    
    // ===================================================
    // CUSTOM ERRORS - Gas Efficient Error Handling
    // ===================================================
    
    /// @notice Thrown when a reentrancy attack is detected
    error SEC_REENTRY();
    /// @notice Thrown when caller is not the contract owner
    error AUTH_OWNER();
    /// @notice Thrown when attempting to set owner to zero address
    error AUTH_ZERO_OWNER();
    /// @notice Thrown when ownership action attempted during 30-day lock period
    error AUTH_LOCKED();
    /// @notice Thrown when new owner is same as current owner
    error AUTH_SAME_OWNER();
    /// @notice Thrown when signature validation fails or signer is unauthorized
    error AUTH_INVALID();
    /// @notice Thrown when caller is not the pending owner during ownership transfer
    error AUTH_NOT_PENDING_OWNER();
    /// @notice Thrown when attempting to cancel a non-existent pending ownership transfer
    error AUTH_NO_PENDING_TRANSFER();
    
    /// @notice Thrown when contract is paused
    error SYS_DISABLED();
    
    /// @notice Thrown when router address is not a contract
    error DEX_ROUTER();
    /// @notice Thrown when factory address is zero
    error DEX_FACTORY_ZERO();
    /// @notice Thrown when factory address is not a contract
    error DEX_FACTORY();
    /// @notice Thrown when WETH address is zero
    error DEX_WETH_ZERO();
    /// @notice Thrown when WETH address is not a contract
    error DEX_WETH();
    /// @notice Thrown when pair address is zero
    error DEX_PAIR_ZERO();
    /// @notice Thrown when pair creation fails
    error DEX_PAIR_FAIL();
    /// @notice Thrown when pair validation fails
    error DEX_PAIR_CHECK();
    /// @notice Thrown when WETH external call fails
    error DEX_WETH_CALL();
    /// @notice Thrown when factory external call fails
    error DEX_FACTORY_CALL();
    /// @notice Thrown when pair address is not a contract
    error DEX_PAIR_NOT_CONTRACT();
    
    /// @notice Thrown when buy tax exceeds 25% (2500 basis points)
    error TAX_BUY_HIGH();
    /// @notice Thrown when sell tax exceeds 25% (2500 basis points)
    error TAX_SELL_HIGH();
    /// @notice Thrown when transfer tax exceeds 25% (2500 basis points)
    error TAX_XFER_HIGH();
    /// @notice Thrown when total of all taxes exceeds 50% (5000 basis points)
    error TAX_TOTAL_HIGH();
    /// @notice Thrown when attempting to change taxes within 24-hour cooldown period
    error TAX_COOLDOWN();
    /// @notice Thrown when buy tax change exceeds 2.5% (250 basis points)
    error TAX_BUY_DELTA();
    /// @notice Thrown when sell tax change exceeds 2.5% (250 basis points)
    error TAX_SELL_DELTA();
    /// @notice Thrown when transfer tax change exceeds 2.5% (250 basis points)
    error TAX_XFER_DELTA();
    /// @notice Thrown when treasury address is zero
    error TAX_TREASURY_ZERO();
    /// @notice Thrown when new treasury is same as current treasury
    error TAX_TREASURY_SAME();
    
    /// @notice Thrown when attempting to blacklist the owner
    error BL_OWNER();
    /// @notice Thrown when attempting to blacklist the contract itself
    error BL_CONTRACT();
    /// @notice Thrown when sender is blacklisted
    error BL_SENDER();
    /// @notice Thrown when recipient is blacklisted
    error BL_RECIPIENT();
    /// @notice Thrown when blacklist expiry timestamp is invalid (in the past)
    error BL_EXPIRY_INVALID();
    
    /// @notice Thrown when whitelist-only mode is enabled and address not whitelisted
    error WL_REQUIRED();
    /// @notice Thrown when whitelist expiry timestamp is invalid (in the past)
    error WL_EXPIRY_INVALID();
    
    /// @notice Thrown when transaction amount is zero
    error TXN_AMOUNT_ZERO();
    /// @notice Thrown when transaction amount exceeds balance
    error TXN_EXCEEDS_BAL();
    /// @notice Thrown when arithmetic operation causes overflow
    error TXN_OVERFLOW();
    /// @notice Thrown when initial supply is zero during deployment
    error TXN_SUPPLY_ZERO();
    /// @notice Thrown when nonce doesn't match expected value (replay attack prevention)
    error TXN_REPLAY();
    /// @notice Thrown when signature has expired past deadline
    error SIG_EXPIRED();
    /// @notice Thrown when internal tax calculation doesn't match expected amount
    error TXN_TAX_MISMATCH();
    
    /// @notice Thrown when 'from' address is zero
    error ADDR_FROM_ZERO();
    /// @notice Thrown when 'to' address is zero
    error ADDR_TO_ZERO();
    /// @notice Thrown when address parameter is invalid or zero
    error ADDR_INVALID();
    /// @notice Thrown when address parameter is zero
    error ADDR_ZERO();
    /// @notice Thrown when address is not a contract (no code at address)
    error ADDR_NOT_CONTRACT();
    
    /// @notice Thrown when approving from zero address
    error APRV_FROM_ZERO();
    /// @notice Thrown when approving to zero address
    error APRV_TO_ZERO();
    /// @notice Thrown when approval amount causes overflow
    error APRV_OVERFLOW();
    /// @notice Thrown when decreasing allowance below zero
    error APRV_UNDERFLOW();
    /// @notice Thrown when allowance is insufficient for operation
    error APRV_INSUFFICIENT();
    
    /// @notice Thrown when attempting to mint to zero address
    error MINT_TO_ZERO();
    /// @notice Thrown when attempting to burn from zero address
    error BURN_FROM_ZERO();
    /// @notice Thrown when burn amount exceeds balance
    error BURN_EXCEEDS();
    
    /// @notice Thrown when transaction velocity limit is exceeded
    error MEV_VELOCITY();
    /// @notice Thrown when transactions are too close together (time-based)
    error MEV_TOO_FAST();
    /// @notice Thrown when MEV protection config requires at least one parameter
    error MEV_CONFIG_INVALID();
    /// @notice Thrown when MEV block limit exceeds maximum (10 blocks)
    error MEV_BLOCKS_HIGH();
    /// @notice Thrown when MEV time limit exceeds maximum (5 minutes)
    error MEV_TIME_HIGH();
    
    /// @notice Thrown when sender is in cooldown period
    error CD_SENDER();
    /// @notice Thrown when recipient is in cooldown period
    error CD_RECIPIENT();
    /// @notice Thrown when seller is in anti-dump cooldown period
    error CD_SELL();
    /// @notice Thrown when cooldown exceeds maximum (1 day)
    error CD_TOO_HIGH();
    
    /// @notice Thrown when anti-dump percentage is invalid (must be 1-100%)
    error DUMP_PERCENT();
    /// @notice Thrown when sell amount exceeds anti-dump limit
    error DUMP_EXCEEDS();
    
    /// @notice Thrown when price impact threshold is below minimum (0.1%)
    error PRICE_MIN_IMPACT();
    /// @notice Thrown when price impact parameter is invalid (0.1-100%)
    error PRICE_INVALID();
    /// @notice Thrown when transaction price impact exceeds limit
    error PRICE_TOO_HIGH();
    
    /// @notice Thrown when category ID is invalid or doesn't exist
    error CAT_INVALID();
    /// @notice Thrown when category is disabled
    error CAT_DISABLED();
    
    /// @notice Thrown when string exceeds maximum length (256 chars)
    error STR_TOO_LONG();
    /// @notice Thrown when string is empty but required
    error STR_EMPTY();
    
    /// @notice Thrown when token address is invalid for emergency withdrawal
    error EMG_INVALID_TOKEN();
    /// @notice Thrown when emergency withdrawal recipient is zero address
    error EMG_ZERO_RECIP();
    /// @notice Thrown when contract has insufficient token balance for withdrawal
    error EMG_INSUF_BAL();
    /// @notice Thrown when emergency token transfer fails
    error EMG_TRANSFER_FAIL();
    /// @notice Thrown when emergency withdrawal attempted before 30-day lock period
    error EMG_WAIT_30D();
    /// @notice Thrown when emergency recipient address is invalid
    error EMG_INVALID_RECIP();
    /// @notice Thrown when contract has insufficient BNB balance
    error EMG_INSUF_BAL_BNB();
    /// @notice Thrown when emergency BNB transfer fails
    error EMG_BNB_FAIL();
    /// @notice Thrown when emergency staking unlock attempted before 1-year period
    error EMG_WAIT_1Y();
    
    /// @notice Thrown when authorized signer is already set
    error AUTH_ALREADY_SET();
    /// @notice Thrown when authorized signer is not set
    error AUTH_NOT_SET();
    /// @notice Thrown when signer address is zero
    error AUTH_ZERO_ADDR();
    
    /// @notice Thrown when transaction attempted during anti-bot period
    error SEC_BOT_ACTIVE();
    
    /// @notice Thrown when velocity config is invalid
    error VEL_CONFIG_INVALID();
    /// @notice Thrown when velocity limit is set too high
    error VEL_LIMIT_HIGH();
    
    /// @notice Thrown when staking contract address is not a contract
    error STAKING_NOT_CONTRACT();
    /// @notice Thrown when attempting to change staking contract with active locks
    error STAKING_ACTIVE_LOCKS();
    
    /// @notice Thrown when trying to switch liquidity collectors without withdrawing pending balance
    error LIQ_COLLECTOR_HAS_BALANCE();

    // ===================================================
    // CONSTRUCTOR
    // ===================================================

    /**
     * @notice Initializes the NTE token contract with essential configuration and protection mechanisms.
     * @dev Constructor performs comprehensive setup in the following order:
     *      1. Validates critical parameters (owner and supply cannot be zero)
     *      2. Sets up ownership and basic token properties (name, symbol, decimals)
     *      3. Configures treasury address (defaults to owner if not specified)
     *      4. Establishes default tax rates: 2% buy, 2% sell, 3% transfer
     *      5. Initializes DEX integration (if router provided)
     *      6. Configures anti-dump and price impact protections
     *      7. Enables MEV protection with conservative defaults
     *      8. Sets up velocity limits (10 tx per 5 minutes)
     *      9. Records deployment timestamp for timelocks
     *      10. Mints initial supply to owner
     *      
     *      Reverts with AUTH_ZERO_OWNER if initialOwner is zero address.
     *      Reverts with TXN_SUPPLY_ZERO if initialSupply is zero.
     *      Reverts with DEX_ROUTER if pancakeRouter is not a valid contract.
     * 
     * @param initialSupply The initial token supply WITHOUT decimals (will be multiplied by 10^18)
     * @param initialOwner The address receiving initial supply and admin privileges (cannot be zero)
     * @param _treasury The address where tax proceeds are sent (zero address defaults to owner)
     * @param _pancakeRouter The PancakeSwap V2 router address for DEX integration (zero address skips DEX setup)
     * 
     * @custom:deployment Deploy with appropriate values for target chain (BSC mainnet/testnet)
     * @custom:defaults Buy: 2%, Sell: 2%, Transfer: 3%, Max sell: 1%, Price impact: 5%
     * @custom:protections MEV protection enabled by default with 2-block and 12-second limits
     * @custom:security All protection mechanisms active from deployment for maximum safety
     * @custom:dex If router provided, attempts to create/find NTE/WBNB pair automatically
     */
    constructor(
        uint256 initialSupply,
        address initialOwner,
        address _treasury,
        address _pancakeRouter
    ) {
        if (initialOwner == address(0)) revert AUTH_ZERO_OWNER();
        if (initialSupply == 0) revert TXN_SUPPLY_ZERO();
        
        _deploymentChainId = block.chainid;
        _owner = initialOwner;
        
        _name = "Node Meta Energy";
        _symbol = "NTE";
        
        treasury = _treasury != address(0) ? _treasury : initialOwner;
        
        buyTaxBps = 200;
        sellTaxBps = 200;
        transferTaxBps = 300;
        
        if (_pancakeRouter != address(0)) {
            if (!_isContract(_pancakeRouter)) revert DEX_ROUTER();
            _initializeDexPair(_pancakeRouter);
            pancakeRouter = _pancakeRouter;
            // Router is NOT tax exempt to prevent arbitrage through direct router calls
        }
        
        maxSellPercentage = 100;
        maxPriceImpactPercent = 500;
        globalCooldownSeconds = 30;
        
        mevProtectionEnabled = true;
        maxBlocksForMevProtection = 2;
        minTimeBetweenTxs = 12;
        
        launchTime = block.timestamp;
        
        maxTxPerWindow = 10;
        velocityTimeWindow = 300;
        
        // Initialize tax change cooldown to deployment time
        _lastTaxChangeTime = block.timestamp;
        
        _mint(initialOwner, initialSupply * 10 ** _decimals);
    }
    
    // ===================================================
    // PUBLIC FUNCTIONS - Standard ERC20 & View Functions
    // ===================================================
    
    /**
     * @notice Returns the name of the token as displayed to users.
     * @dev Returns the full token name string stored in _name state variable.
     * @return name The full name string: "Node Meta Energy"
     * @custom:view Pure view function with no state modifications
     */
    function name() external view returns (string memory) {
        return _name;
    }
    
    /**
     * @notice Returns the symbol/ticker of the token for exchanges and wallets.
     * @dev Returns the token symbol string stored in _symbol state variable.
     * @return symbol The token ticker symbol: "NTE"
     * @custom:view Pure view function with no state modifications
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }
    
    /**
     * @notice Returns the number of decimal places for token amounts.
     * @dev All token amounts should be multiplied by 10^18 for correct display.
     *      This follows the standard ERC20 decimals convention.
     * @return decimals Always returns 18 as a constant value
     * @custom:standard ERC20 standard implementation with 18 decimals
     */
    function decimals() external pure returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Returns the total circulating supply of NTE tokens.
     * @dev This is the sum of all tokens currently in existence, excluding burned tokens.
     *      Initial supply is minted at deployment and decreases when tokens are burned.
     * @return supply The total amount of tokens in circulation (in base units with 18 decimals)
     * @custom:formula totalSupply = initialSupply - totalBurned + anyMints
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @notice Returns the token balance of a specific address.
     * @dev Returns the amount from _balances mapping minus any locked staking tokens.
     *      The returned balance is freely transferable (excluding staked amounts).
     * @param account The address to query the balance for
     * @return balance The amount of tokens held by the account (in base units with 18 decimals)
     * @custom:note Balance doesn't include tokens locked in staking contract
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @notice Transfers tokens from caller to recipient address with applicable taxes.
     * @dev Triggers _transferWithTax which handles all protections, taxes, and validations.
     *      Tax rates depend on recipient type (DEX pair, regular wallet, etc.).
     * @param to The address receiving the tokens (cannot be zero address)
     * @param amount The amount of tokens to transfer (in base units with 18 decimals)
     * @return success Always returns true on successful transfer, reverts on failure
     * @custom:taxes May apply buy/sell/transfer tax based on recipient type
     * @custom:protections Enforces all active protections (MEV, velocity, blacklist, etc.)
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithTax(msg.sender, to, amount);
        return true;
    }
    
    /**
     * @notice Returns the remaining allowance  that spender can transfer from owner.
     * @dev Returns 0 if no allowance set, or the remaining amount if allowance exists.
     *      Max uint256 represents infinite allowance (commonly used for contracts).
     * @param account The address that owns the tokens
     * @param spender The address authorized to spend the tokens
     * @return remaining The amount of tokens spender can still transfer on behalf of account
     * @custom:standard Standard ERC20 allowance mechanism
     */
    function allowance(address account, address spender) public view override returns (uint256) {
        return _allowances[account][spender];
    }
    
    /**
     * @notice Approves an address to spend tokens on behalf of the caller.
     * @dev Sets the allowance for spender to transfer up to amount tokens from msg.sender.
     *      Setting to max uint256 creates an infinite approval (gas efficient for contracts).
     *      Emits an {Approval} event on successful approval.
     * @param spender The address being authorized to spend tokens
     * @param amount The maximum amount spender can transfer (use type(uint256).max for infinite)
     * @return success Always returns true on successful approval, reverts on failure
     * @custom:security Consider using increaseAllowance/decreaseAllowance to prevent front-running
     * @custom:standard Standard ERC20 approval mechanism
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @notice Transfers tokens from one address to another using a pre-approved allowance.
     * @dev Spends allowance using _spendAllowance then executes transfer with _transferWithTax.
     *      The caller must have sufficient allowance from the from address to perform this operation.
     *      Applies all taxes and protections just like a regular transfer.
     * @param from The address to transfer tokens from (must have approved caller)
     * @param to The address to transfer tokens to (cannot be zero address)
     * @param amount The amount of tokens to transfer (in base units with 18 decimals)
     * @return success Always returns true on successful transfer, reverts on insufficient allowance
     * @custom:taxes May apply buy/sell/transfer tax based on addresses
     * @custom:allowance Automatically decreases allowance by amount (unless infinite)
     * @custom:usage Common for DEX swaps and smart contract integrations
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferWithTax(from, to, amount);
        return true;
    }

    // ===================================================
    // PAYMENT CATEGORIZATION TRANSFER FUNCTIONS
    // ===================================================
    
    /**
     * @notice Executes a categorized token transfer with off-chain authorization and metadata tracking.
     * @dev This function enables gas-less or delegated transfers with category tracking.
     *      An off-chain authorized signer (backend service) signs the transaction parameters,
     *      allowing a relayer to execute the transaction while maintaining security.
     *      
     *      **Flow:**
     *      1. Off-chain backend signs: (contract, from, to, amount, category, txRef, nonce, deadline, chainId)
     *      2. `from` address grants allowance to caller (relayer/helper) once
     *      3. Relayer calls transactionFrom() and pays gas on behalf of `from`
     *      4. Contract validates signature and processes transfer with category metadata
     *      
     *      **Security measures:**
     *      - Per-address nonce (userCategorizedNonce[from]) prevents replay attacks
     *      - Deadline timestamp ensures signatures expire and can't be used indefinitely
     *      - Signature bound to specific contract address and chain ID
     *      - Category must be enabled and within valid range
     *      - All standard transfer protections apply (taxes, MEV, velocity, etc.)
     * 
     * @param from The address whose tokens are being transferred (must have approved caller)
     * @param to The address receiving the tokens (cannot be zero address)
     * @param amount The amount of tokens to transfer (in base units with 18 decimals)
     * @param category The category ID for this transaction (0-254, must be enabled)
     * @param signature ECDSA signature from authorized signer (65 bytes: r, s, v)
     * @param nonce Expected nonce for the `from` address (must match current nonce)
     * @param deadline Unix timestamp after which signature expires
     * @param txReference External reference (invoice/order number, max 64 chars)
     * @param memo Transaction note or description (max 64 chars)
     * @return success Always returns true on successful execution, reverts on failure
     * 
     * @custom:security Signature validation with malleability checks and nonce enforcement
     * @custom:categories Automatically updates category statistics and user metrics
     * @custom:allowance Spends allowance from `from` to caller before processing transfer
     * @custom:emit TransactionProcessed and CategoryStatsUpdated events
     */
    function transactionFrom(
        address from,
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        if (from == address(0)) revert ADDR_FROM_ZERO();
        if (to == address(0)) revert ADDR_TO_ZERO();
        if (amount == 0) revert TXN_AMOUNT_ZERO();
        if (block.timestamp > deadline) revert SIG_EXPIRED();

        uint256 expectedNonce = userCategorizedNonce[from];
        if (nonce != expectedNonce) revert TXN_REPLAY();

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                address(this),
                from,
                to,
                amount,
                category,
                txReference,
                nonce,
                deadline,
                _deploymentChainId
            )
        );

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address signer = _recoverSigner(ethSignedMessageHash, signature);
        if (signer == address(0)) revert AUTH_ZERO_ADDR();
        if (!isAuthSigner[signer]) revert AUTH_INVALID();

        if (category >= totalCategories) revert CAT_INVALID();
        if (!categoryEnabled[category]) revert CAT_DISABLED();

        if (bytes(txReference).length > MAX_STRING_LENGTH) revert STR_TOO_LONG();
        if (bytes(memo).length > MAX_STRING_LENGTH) revert STR_TOO_LONG();

        _spendAllowance(from, msg.sender, amount);
        _transferWithTax(from, to, amount);

        unchecked {
            if (categoryTransactionCount[category] >= type(uint256).max) revert TXN_OVERFLOW();
            categoryTransactionCount[category]++;

            if (categoryTotalVolume[category] > type(uint256).max - amount) revert TXN_OVERFLOW();
            categoryTotalVolume[category] += amount;

            if (userCategoryCount[from][category] >= type(uint256).max) revert TXN_OVERFLOW();
            userCategoryCount[from][category]++;

            if (userCategoryVolume[from][category] > type(uint256).max - amount) revert TXN_OVERFLOW();
            userCategoryVolume[from][category] += amount;
        }

        userCategorizedNonce[from] = expectedNonce + 1;

        emit TransactionProcessed(from, to, amount, category, txReference, memo);
        emit CategoryStatsUpdated(category, categoryTransactionCount[category], categoryTotalVolume[category]);

        return true;
    }
    
    /**
     * @notice Returns the display name of a specific payment category.
     * @dev Reverts with CAT_INVALID if category ID is out of bounds.
     * @param category The category ID to query (must be less than totalCategories)
     * @return name The human-readable category name string (e.g., "Business", "Rewards")
     * @custom:view Pure read operation with category bounds validation
     */
    function getCategoryName(uint8 category) external view returns (string memory) {
        if (category >= totalCategories) revert CAT_INVALID();
        return categoryNames[category];
    }
    
    /**
     * @notice Enables or disables a specific payment category for new transactions.
     * @dev Disabled categories cannot be used in transactionFrom calls.
     *      Existing transactions with that category are still recorded in history.
     *      Reverts with CAT_INVALID if category ID is out of bounds.
     * @param category The category ID to update (must be less than totalCategories)
     * @param enabled True to allow transactions in this category, false to block
     * @custom:access Only callable by contract owner
     * @custom:emit CategoryStatusUpdated event
     */
    function setCategoryEnabled(uint8 category, bool enabled) external onlyOwner {
        if (category >= totalCategories) revert CAT_INVALID();
        categoryEnabled[category] = enabled;
        emit CategoryStatusUpdated(category, enabled);
    }
    
    /**
     * @notice Updates the display name of an existing payment category.
     * @dev Useful for rebranding or fixing typos in category names.
     *      Reverts with CAT_INVALID if category doesn't exist, STR_EMPTY if name is empty,
     *      or STR_TOO_LONG if name exceeds MAX_STRING_LENGTH (64 characters).
     * @param category The category ID to rename (must be less than totalCategories)
     * @param newName The new display name for this category (1-64 characters)
     * @custom:access Only callable by contract owner
     * @custom:validation Name must be non-empty and within length limits
     * @custom:emit CategoryUpdated event
     */
    function updateCategoryName(uint8 category, string calldata newName) external onlyOwner {
        if (category >= totalCategories) revert CAT_INVALID();
        if (bytes(newName).length == 0) revert STR_EMPTY();
        if (bytes(newName).length > MAX_STRING_LENGTH) revert STR_TOO_LONG();
        categoryNames[category] = newName;
        emit CategoryUpdated(category, newName);
    }
    
    /**
     * @notice Adds a new payment category to the system for transaction classification.
     * @dev Creates a new category with auto-incremented ID starting from 0.
     *      Maximum of 255 categories can be created (uint8 limit).
     *      New categories are automatically enabled when created.
     *      Reverts with STR_EMPTY if name is empty, STR_TOO_LONG if exceeds 64 chars,
     *      or CAT_INVALID if already at maximum category count.
     * @param categoryName The display name for the new category (1-64 characters)
     * @return categoryId The newly assigned category ID (0-254)
     * @custom:access Only callable by contract owner
     * @custom:effects Increments totalCategories counter and enables new category
     * @custom:emit CategoryAdded event with new ID and name
     */
    function addCategory(string calldata categoryName) external onlyOwner returns (uint8 categoryId) {
        if (bytes(categoryName).length == 0) revert STR_EMPTY();
        if (bytes(categoryName).length > MAX_STRING_LENGTH) revert STR_TOO_LONG();
        if (totalCategories == 255) revert CAT_INVALID();
        
        categoryId = totalCategories;
        categoryNames[categoryId] = categoryName;
        categoryEnabled[categoryId] = true;
        totalCategories++;
        
        emit CategoryAdded(categoryId, categoryName);
        return categoryId;
    }

    /**
     * @notice Authorizes a new off-chain signer for categorized transfer validation.
     * @dev Signer addresses should be managed securely using HSM, KMS, or secure backend.
     *      Only authorized signers can create valid signatures for transactionFrom calls.
     *      Reverts with ADDR_ZERO if address is zero, or AUTH_ALREADY_SET if already authorized.
     * @param authAddress The backend service or signer address to authorize (cannot be zero)
     * @custom:access Only callable by contract owner
     * @custom:security Store private keys in secure infrastructure (HSM/KMS recommended)
     * @custom:emit AuthSignerAdded event
     */
    function addAuthSigner(address authAddress) external onlyOwner {
        if (authAddress == address(0)) revert ADDR_ZERO();
        if (isAuthSigner[authAddress]) revert AUTH_ALREADY_SET();
        isAuthSigner[authAddress] = true;
        emit AuthSignerAdded(authAddress);
    }

    /**
     * @notice Revokes authorization from an off-chain signer for categorized transfers.
     * @dev Immediately invalidates all future signatures from this address.
     *      Previously signed but unexecuted transactions will fail validation.
     *      Reverts with AUTH_NOT_SET if address was not previously authorized.
     * @param authAddress The signer address to remove from authorized list
     * @custom:access Only callable by contract owner
     * @custom:effect Immediately blocks all new signatures from this address
     * @custom:emit AuthSignerRemoved event
     */
    function removeAuthSigner(address authAddress) external onlyOwner {
        if (!isAuthSigner[authAddress]) revert AUTH_NOT_SET();
        isAuthSigner[authAddress] = false;
        emit AuthSignerRemoved(authAddress);
    }

    /**
     * @notice Burns tokens from the caller's balance, permanently removing them from circulation.
     * @dev Destroys tokens by transferring them to the zero address and reducing total supply.
     *      Burned tokens are tracked in the totalBurned counter for transparency.
     *      This is a one-way operation - burned tokens cannot be recovered.
     *      Caller must have sufficient unlocked balance (not staked) to burn.
     *      Reverts with BURN_FROM_ZERO if caller is zero address (impossible in practice),
     *      or BURN_EXCEEDS if amount exceeds caller's available balance.
     * @param amount The number of tokens to permanently destroy (in base units with 18 decimals)
     * @custom:effects Decreases total supply, caller balance, and increases totalBurned counter
     * @custom:permanent Burned tokens are permanently removed and cannot be recovered
     * @custom:emit Transfer event to zero address indicating token destruction
     * @custom:usage Common for tokenomics models with deflationary mechanisms
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    /**
     * @notice Checks if the contract is currently in a paused state.
     * @dev Returns the current value of the _paused state variable.
     *      When paused, all token transfers are blocked (except potentially owner
     *      based on pauseIncludesOwner flag). Used to check contract status before
     *      attempting transfers or for UI/frontend conditional rendering.
     * @return isPaused True if contract is paused and transfers are blocked, false if operating normally
     * @custom:view Read-only function with no state modifications or gas cost (when called externally)
     * @custom:usage Check before transfers, display in UI, or integrate with frontend logic
     */
    function paused() external view returns (bool) {
        return _paused;
    }
    
    /**
     * @notice Returns the address of the current contract owner with admin privileges.
     * @dev Returns the _owner state variable which can be zero address if ownership
     *      has been renounced via renounceOwnership(). Owner has exclusive access to
     *      all admin functions (onlyOwner modifier), including pause, tax changes,
     *      blacklist management, and configuration updates.
     * @return ownerAddress The address of current owner, or zero address if ownership renounced
     * @custom:view Read-only function with no state modifications or gas cost
     * @custom:governance Owner controls all admin functions and protocol parameters
     * @custom:renouncement Returns zero address if ownership has been permanently renounced
     */
    function owner() external view returns (address) {
        return _owner;
    }
    

    /**
     * @notice Returns a comprehensive snapshot of the current tax configuration and exemptions.
     * @dev Provides all tax-related settings in a single call for efficient frontend integration.
     *      Tax rates are returned in basis points where 100 = 1%, 1000 = 10%, etc.
     *      Router and pair exemption status indicates whether these critical addresses
     *      bypass tax collection (typically router is NOT exempt, pair is NOT exempt).
     *      This function is gas-efficient for dashboards and UI displaying tax info.
     * @return buyTax Buy transaction tax rate in basis points (0-2500, typically 200 = 2%)
     * @return sellTax Sell transaction tax rate in basis points (0-2500, typically 200 = 2%)
     * @return transferTax Wallet-to-wallet transfer tax rate in basis points (0-2500, typically 300 = 3%)
     * @return treasuryAddr The destination address receiving all collected tax proceeds
     * @return routerExempt True if PancakeSwap router bypasses taxes (typically false)
     * @return pairExempt True if main liquidity pair bypasses taxes (typically false)
     * @custom:view Read-only aggregation function with no state modifications
     * @custom:usage Ideal for frontend tax calculators, dashboards, and transaction previews
     * @custom:basis 100 basis points = 1%, maximum 2500 = 25% per tax type
     */
    function getTaxConfiguration() external view returns (
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
     * @notice Pauses all token transfers and trading operations.
     * @dev Sets paused state to true, blocking transfers based on includeOwner flag.
     *      When includeOwner is true, even owner transactions are blocked.
     *      When false, owner can still transfer during emergency.
     *      Used during security incidents, upgrades, or critical issues.
     * @param includeOwner If true, owner is also blocked; if false, owner can still transfer
     * @custom:security Emergency brake for critical issues or security incidents
     * @custom:access Only callable by contract owner via onlyOwner modifier
     * @custom:effect Blocks all transfers except potentially owner (based on flag)
     * @custom:emit Paused event with msg.sender
     */
    function pause(bool includeOwner) external onlyOwner {
        _paused = true;
        pauseIncludesOwner = includeOwner;
        emit Paused(msg.sender);
    }
    
    /**
     * @notice Resumes all token transfers and trading operations after pause.
     * @dev Sets paused state and pauseIncludesOwner to false, fully restoring operations.
     *      Used to resume normal trading after emergency or maintenance is resolved.
     * @custom:security Restores normal operations after emergency pause
     * @custom:access Only callable by contract owner via onlyOwner modifier
     * @custom:effect Allows all transfers to proceed normally
     * @custom:emit Unpaused event with msg.sender
     */
    function unpause() external onlyOwner {
        _paused = false;
        pauseIncludesOwner = false;
        emit Unpaused(msg.sender);
    }
    
    /**
     * @notice Renounces contract ownership permanently, making the contract ownerless.
     * @dev This is an irreversible operation that removes all owner privileges.
     *      Safety restrictions:
     *      - Cannot renounce while paused (prevents permanent lock)
     *      - Must wait 30 days after launch (OWNERSHIP_LOCK_PERIOD)
     *      After renouncement, no admin functions can ever be called again.
     * @custom:access Only callable by current owner
     * @custom:security 30-day timelock prevents accidental early renouncement
     * @custom:irreversible Cannot be undone - contract becomes fully decentralized
     * @custom:emit OwnershipTransferred event with zero address as new owner
     */
    function renounceOwnership() external onlyOwner {
        if (_paused) revert SYS_DISABLED();
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert AUTH_LOCKED();
        address previousOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }
    
    /**
     * @notice Initiates a two-step ownership transfer to a new address.
     * @dev Step 1 of 2-step ownership transfer process. The new owner must call
     *      acceptOwnership() to complete the transfer. This prevents accidental
     *      transfers to wrong addresses or addresses that can't accept ownership.
     *      Reverts with AUTH_ZERO_OWNER if newOwner is zero address,
     *      or AUTH_SAME_OWNER if newOwner is already the current owner.
     * @param newOwner The address that will become the new owner (cannot be zero or current owner)
     * @custom:access Only callable by current owner
     * @custom:security Two-step process prevents accidental ownership loss
     * @custom:emit OwnershipTransferStarted event to signal pending transfer
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert AUTH_ZERO_OWNER();
        if (newOwner == _owner) revert AUTH_SAME_OWNER();
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }
    
    /**
     * @notice Accepts a pending ownership transfer to complete the two-step process.
     * @dev Step 2 of 2-step ownership transfer. Can only be called by the pending owner
     *      set in transferOwnership(). Completes the ownership transfer and grants
     *      full admin privileges to caller.
     *      Reverts with AUTH_NOT_PENDING_OWNER if caller is not the pending owner.
     * @custom:access Only callable by pending owner address
     * @custom:security Prevents unauthorized ownership takeover
     * @custom:emit OwnershipTransferred event with old and new owner addresses
     */
    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert AUTH_NOT_PENDING_OWNER();
        address previousOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, _owner);
    }
    
    /**
     * @notice Cancels a pending ownership transfer before it's accepted.
     * @dev Allows current owner to revoke an ownership transfer that was initiated
     *      but not yet accepted. Clears the pending owner address.
     * @custom:access Only callable by current owner
     * @custom:effect Resets pending owner to zero address
     * @custom:emit OwnershipTransferCanceled event
     */
    function cancelOwnershipTransfer() external onlyOwner {
        if (_pendingOwner == address(0)) revert AUTH_NO_PENDING_TRANSFER();
        _pendingOwner = address(0);
        emit OwnershipTransferStarted(_owner, address(0));
    }
    
    /**
     * @notice Returns the address of the pending owner in a two-step ownership transfer.
     * @dev Queries the _pendingOwner state variable set during transferOwnership().
     *      A non-zero return value indicates an ownership transfer is in progress.
     *      The pending owner must call acceptOwnership() to complete the transfer.
     *      Returns zero address when no transfer is pending or after completion/cancellation.
     * @return pendingOwnerAddress The address authorized to accept ownership, or zero if no transfer pending
     * @custom:view Read-only function with no state modifications or gas cost
     * @custom:usage Check transfer status before accepting or monitor pending transfers
     * @custom:security Part of two-step ownership transfer security mechanism
     */
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }
    
    /**
     * @notice Calculates the net proceeds, tax amount, and price impact for a potential sell transaction.
     * @dev Provides transparent pre-transaction simulation for sell operations.
     *      This view function allows users and frontends to preview exact outcomes before executing.
     *      
     *      **Calculation steps:**
     *      1. Apply sell tax: taxAmount = (amount × sellTaxBps) / 10000
     *      2. Calculate net: netOutput = amount - taxAmount
     *      3. Query AMM: impactBps = price impact based on current liquidity pool ratios
     *      
     *      **Price impact calculation:**
     *      Uses constant product formula (x × y = k) from PancakeSwap pair reserves.
     *      Higher amounts or lower liquidity result in higher price impact.
     *      Impact is returned in basis points where 100 = 1% price movement.
     *      
     *      Reverts with TXN_AMOUNT_ZERO if amount is zero.
     * @param amount The number of tokens to simulate selling (in base units with 18 decimals)
     * @return netOutput Tokens received after sell tax deduction (what you actually get)
     * @return taxAmount Tokens deducted as sell tax and sent to treasury
     * @return impactBps Estimated price impact in basis points (100 = 1%, 500 = 5%)
     * @custom:view Read-only simulation with no state changes or execution
     * @custom:transparency Essential for informed trading decisions and price discovery
     * @custom:usage Frontend displays, trading bots, price impact warnings, user education
     * @custom:basis Impact in basis points: 10 = 0.1%, 100 = 1%, 1000 = 10%
     */
    function checkSellability(uint256 amount) external view returns (
        uint256 netOutput,
        uint256 taxAmount,
        uint256 impactBps
    ) {
        if (amount == 0) revert TXN_AMOUNT_ZERO();
        
        // 1. Calculate Tax
        taxAmount = (amount * sellTaxBps) / BASIS_POINTS;
        netOutput = amount - taxAmount;
        
        // 2. Calculate Price Impact
        impactBps = _calculatePriceImpact(amount, pancakePair);
        
        return (netOutput, taxAmount, impactBps);
    }

    /**
     * @notice Updates all three tax rates (buy, sell, transfer) in a single transaction.
     * @dev Subject to multiple safety validations:
     *      - Individual tax cannot exceed MAX_TAX_LIMIT (2500 = 25%)
     *      - Combined total cannot exceed MAX_TOTAL_TAX_LIMIT (5000 = 50%)
     *      - Changes cannot exceed MAX_TAX_CHANGE_DELTA (500 = 5%) per tax type
     *      - Must respect TAX_CHANGE_COOLDOWN (24 hours) between changes
     *      All rates are in basis points (100 = 1%, 2500 = 25%).
     * @param newBuyTaxBps New tax rate for buy transactions (0-2500, max 25%)
     * @param newSellTaxBps New tax rate for sell transactions (0-2500, max 25%)
     * @param newTransferTaxBps New tax rate for wallet-to-wallet transfers (0-2500, max 25%)
     * @custom:access Only callable by contract owner
     * @custom:validation Multiple limits prevent sudden tax changes and protect investors
     * @custom:cooldown 24-hour cooldown between tax adjustments
     * @custom:emit TaxRatesUpdated event with all three new rates
     */
    function setAllTaxBasisPoints(
        uint256 newBuyTaxBps,
        uint256 newSellTaxBps,
        uint256 newTransferTaxBps
    ) external onlyOwner {
        if (newBuyTaxBps > MAX_TAX_LIMIT) revert TAX_BUY_HIGH();
        if (newSellTaxBps > MAX_TAX_LIMIT) revert TAX_SELL_HIGH();
        if (newTransferTaxBps > MAX_TAX_LIMIT) revert TAX_XFER_HIGH();
        if (newBuyTaxBps + newSellTaxBps + newTransferTaxBps > MAX_TOTAL_TAX_LIMIT) revert TAX_TOTAL_HIGH();
        if (block.timestamp < _lastTaxChangeTime + TAX_CHANGE_COOLDOWN) revert TAX_COOLDOWN();
        
        uint256 buyChange = newBuyTaxBps > buyTaxBps ? newBuyTaxBps - buyTaxBps : buyTaxBps - newBuyTaxBps;
        uint256 sellChange = newSellTaxBps > sellTaxBps ? newSellTaxBps - sellTaxBps : sellTaxBps - newSellTaxBps;
        uint256 transferChange = newTransferTaxBps > transferTaxBps ? newTransferTaxBps - transferTaxBps : transferTaxBps - newTransferTaxBps;
        
        if (buyChange > MAX_TAX_CHANGE_DELTA) revert TAX_BUY_DELTA();
        if (sellChange > MAX_TAX_CHANGE_DELTA) revert TAX_SELL_DELTA();
        if (transferChange > MAX_TAX_CHANGE_DELTA) revert TAX_XFER_DELTA();
        
        buyTaxBps = newBuyTaxBps;
        sellTaxBps = newSellTaxBps;
        transferTaxBps = newTransferTaxBps;
        _lastTaxChangeTime = block.timestamp;
        
        emit TaxRatesUpdated(newBuyTaxBps, newSellTaxBps, newTransferTaxBps);
    }
    
    /**
     * @notice Configures automatic liquidity provision routing from collected tax proceeds.
     * @dev Enables splitting tax proceeds between treasury and a dedicated liquidity manager contract.
     *      This advanced feature automates liquidity addition without manual intervention.
     *      
     *      **Tax routing flow:**
     *      - Percentage (percentageBps) of each tax goes to liquidity collector
     *      - Remainder automatically goes to treasury address
     *      - Example: 30% (3000 bps) to liquidity, 70% to treasury
     *      
     *      **Safety validations:**
     *      - Collector must be a contract (verified with _isContract check)
     *      - Cannot be zero address when enabling
     *      - Percentage must be 1-10000 basis points (0.01%-100%)
     *      - When switching collectors, old collector must have zero balance
     *      
     *      **Exemption management:**
     *      When changing collectors, automatically:
     *      1. Removes ALL exemptions from old collector (tax, MEV, velocity, price impact, whitelist)
     *      2. Grants ALL exemptions to new collector for smooth operation
     *      
     *      This ensures liquidity manager can operate freely without restrictions while
     *      preventing abandoned collectors from retaining privileged status.
     *      
     *      Reverts with PRICE_INVALID if percentageBps > 10000 or equals 0 when enabling,
     *      ADDR_ZERO if collector is zero when enabling,
     *      ADDR_NOT_CONTRACT if collector is not a contract,
     *      or LIQ_COLLECTOR_HAS_BALANCE if trying to switch with pending balance.
     * @param enabled True to enable tax routing to liquidity manager, false to disable (all to treasury)
     * @param percentageBps Percentage of tax to route to collector in basis points (100 = 1%, 3000 = 30%)
     * @param collector Address of liquidity manager contract (must be contract, not EOA)
     * @custom:access Only callable by contract owner
     * @custom:reentrancy Protected by nonReentrant modifier to prevent reentrancy attacks
     * @custom:exemptions Automatically grants all protections to collector (tax, MEV, velocity, price impact, whitelist)
     * @custom:migration When switching collectors, old collector must withdraw all tokens first
     * @custom:usage Ideal for: auto-liquidity, buyback-and-LP, protocol-owned liquidity (POL)
     * @custom:emit AutoLiquidityConfigUpdated and multiple exemption events during setup
     */
    function configureAutoLiquidity(
        bool enabled,
        uint256 percentageBps,
        address collector
    ) external onlyOwner nonReentrant {
        if (percentageBps > BASIS_POINTS) revert PRICE_INVALID();
        
        address oldCollector = liquidityCollector;
        
        if (enabled) {
            if (collector == address(0)) revert ADDR_ZERO();
            if (!_isContract(collector)) revert ADDR_NOT_CONTRACT();
            if (percentageBps == 0) revert PRICE_INVALID();
            
            // Prevent switching collectors if old collector has pending balance
            if (oldCollector != address(0) && oldCollector != collector && balanceOf(oldCollector) > 0) {
                revert LIQ_COLLECTOR_HAS_BALANCE();
            }
            
            // Clean up old collector exemptions if changing to a different collector
            if (oldCollector != address(0) && oldCollector != collector) {
                if (taxExempt[oldCollector]) {
                    taxExempt[oldCollector] = false;
                    emit TaxExemptUpdated(oldCollector, false);
                }
                if (mevProtectionExempt[oldCollector]) {
                    mevProtectionExempt[oldCollector] = false;
                    emit MevProtectionExemptUpdated(oldCollector, false);
                }
                if (velocityLimitExempt[oldCollector]) {
                    velocityLimitExempt[oldCollector] = false;
                    emit VelocityLimitExemptUpdated(oldCollector, false);
                }
                if (priceImpactExempt[oldCollector]) {
                    priceImpactExempt[oldCollector] = false;
                    emit PriceImpactExemptUpdated(oldCollector, false);
                }
                if (isWhitelisted[oldCollector]) {
                    isWhitelisted[oldCollector] = false;
                    whitelistExpiry[oldCollector] = 0;
                    emit WhitelistUpdated(oldCollector, false);
                }
            }

            // Grant all exemptions to new liquidity collector
            if (!taxExempt[collector]) {
                taxExempt[collector] = true;
                emit TaxExemptUpdated(collector, true);
            }
            if (!mevProtectionExempt[collector]) {
                mevProtectionExempt[collector] = true;
                emit MevProtectionExemptUpdated(collector, true);
            }
            if (!velocityLimitExempt[collector]) {
                velocityLimitExempt[collector] = true;
                emit VelocityLimitExemptUpdated(collector, true);
            }
            if (!priceImpactExempt[collector]) {
                priceImpactExempt[collector] = true;
                emit PriceImpactExemptUpdated(collector, true);
            }
            if (!isWhitelisted[collector] || whitelistExpiry[collector] != 0) {
                isWhitelisted[collector] = true;
                whitelistExpiry[collector] = 0;
                emit WhitelistUpdated(collector, true);
            }
        } else {
            if (collector != address(0) && !_isContract(collector)) revert ADDR_NOT_CONTRACT();
        }

        autoLiquidityEnabled = enabled;
        autoLiquidityBps = percentageBps;
        liquidityCollector = collector;
        emit AutoLiquidityConfigUpdated(enabled, percentageBps, collector);
    }
    
    /**
     * @notice Sets the tax exemption status for a specific address.
     * @dev Tax-exempt addresses don't pay buy/sell/transfer taxes on their transactions.
     *      Typically granted to DEX routers (PancakeSwap), liquidity managers,
     *      treasury addresses, and other protocol infrastructure contracts.
     *      Reverts with ADDR_INVALID if user is zero address.
     * @param user The address to grant or revoke tax exemption (cannot be zero)
     * @param exempt True to exempt from all taxes, false to apply standard tax rates
     * @custom:access Only callable by contract owner
     * @custom:usage Grant to: routers, pairs, liquidity managers, authorized contracts
     * @custom:emit TaxExemptUpdated event
     */
    function setTaxExempt(address user, bool exempt) external onlyOwner {
        if (user == address(0)) revert ADDR_INVALID();
        taxExempt[user] = exempt;
        emit TaxExemptUpdated(user, exempt);
    }
    
    /**
     * @notice Manages the blacklist status for a specific address with optional expiry.
     * @dev Blacklisted addresses cannot send or receive tokens (blocked from all transfers).
     *      Used to block malicious actors, stolen wallets, or sanctioned addresses.
     *      Supports temporary blacklisting with automatic expiry timestamp.
     *      Cannot blacklist owner or contract itself for safety.
     *      Reverts with ADDR_INVALID if account is zero,
     *      BL_OWNER if trying to blacklist owner,
     *      BL_CONTRACT if trying to blacklist contract,
     *      or BL_EXPIRY_INVALID if expiry is in the past.
     * @param account The address to blacklist or unblacklist (cannot be zero/owner/contract)
     * @param blacklisted True to block all transfers, false to restore transfer rights
     * @param expiryTime Unix timestamp when blacklist auto-expires (0 = permanent)
     * @custom:access Only callable by contract owner
     * @custom:security Prevents scammers, stolen funds movement, and sanctioned addresses
     * @custom:temporary Set expiryTime > 0 for temporary bans that auto-expire
     * @custom:emit BlacklistUpdated and optionally BlacklistExpirySet events
     */
    function setBlacklist(address account, bool blacklisted, uint256 expiryTime) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        if (account == _owner) revert BL_OWNER();
        if (account == address(this)) revert BL_CONTRACT();
        isBlacklisted[account] = blacklisted;
        if (blacklisted && expiryTime > 0) {
            if (expiryTime <= block.timestamp) revert BL_EXPIRY_INVALID();
            blacklistExpiry[account] = expiryTime;
            emit BlacklistExpirySet(account, expiryTime);
        } else {
            blacklistExpiry[account] = 0;
        }
        emit BlacklistUpdated(account, blacklisted);
    }

    /**
     * @notice Toggles whitelist-only trading mode for controlled launch periods.
     * @dev When enabled, only whitelisted addresses can participate in trading.
     *      Used during private sales, controlled launches, or compliance requirements.
     *      When disabled, all non-blacklisted addresses can trade freely.
     *      Whitelist status is checked separately via isWhitelistedActive().
     * @param enabled True to restrict trading to whitelisted addresses only, false for open trading
     * @custom:access Only callable by contract owner
     * @custom:usage Common for: private sales, KYC periods, controlled launches
     * @custom:effect When enabled, non-whitelisted addresses cannot trade
     * @custom:emit WhitelistModeUpdated event
     */
    function setWhitelistMode(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistModeUpdated(enabled);
    }

    /**
     * @notice Manages the whitelist status for a specific address with optional expiry.
     * @dev Whitelisted addresses can trade when whitelistEnabled is true.
     *      Supports temporary whitelisting with automatic expiry timestamp.
     *      Used for controlled launches, private sales, or compliance requirements.
     *      Reverts with ADDR_INVALID if account is zero,
     *      or WL_EXPIRY_INVALID if expiry is in the past.
     * @param account The address to whitelist or unwhitelist (cannot be zero)
     * @param whitelisted True to grant trading permission, false to revoke
     * @param expiryTime Unix timestamp when whitelist auto-expires (0 = permanent)
     * @custom:access Only callable by contract owner
     * @custom:usage Grant to: early investors, KYC-verified users, partners
     * @custom:temporary Set expiryTime > 0 for time-limited trading permissions
     * @custom:emit WhitelistUpdated and optionally WhitelistExpirySet events
     */
    function setWhitelist(address account, bool whitelisted, uint256 expiryTime) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        isWhitelisted[account] = whitelisted;
        if (whitelisted && expiryTime > 0) {
            if (expiryTime <= block.timestamp) revert WL_EXPIRY_INVALID();
            whitelistExpiry[account] = expiryTime;
            emit WhitelistExpirySet(account, expiryTime);
        } else {
            whitelistExpiry[account] = 0;
        }
        emit WhitelistUpdated(account, whitelisted);
    }

    /**
     * @notice Updates the treasury address where collected taxes are sent.
     * @dev Treasury receives all tax proceeds from buy/sell/transfer operations.
     *      Reverts with TAX_TREASURY_ZERO if new address is zero,
     *      or TAX_TREASURY_SAME if address hasn't changed.
     * @param newTreasury The new treasury wallet address (cannot be zero or same as current)
     * @custom:access Only callable by contract owner
     * @custom:effect All future tax proceeds will be sent to new treasury address
     * @custom:emit TreasuryUpdated event with new address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert TAX_TREASURY_ZERO();
        if (newTreasury == treasury) revert TAX_TREASURY_SAME();
        
        treasury = newTreasury;
        
        emit TreasuryUpdated(newTreasury);
    }

    /**
     * @notice Updates the token name and symbol for rebranding or corrections.
     * @dev Changes the human-readable token name and trading symbol.
     *      Both names must be non-empty and within MAX_STRING_LENGTH (64 characters).
     *      This is useful for rebranding, fixing typos, or market repositioning.
     *      Reverts with STR_EMPTY if either string is empty,
     *      or STR_TOO_LONG if either exceeds 64 characters.
     * @param newName The new full token name (e.g., "Node Meta Energy", 1-64 chars)
     * @param newSymbol The new token ticker symbol (e.g., "NTE", 1-64 chars)
     * @custom:access Only callable by contract owner
     * @custom:visibility Updates name() and symbol() view functions immediately
     * @custom:emit NameSymbolUpdated event with both new values
     */
    function setNameAndSymbol(string calldata newName, string calldata newSymbol) external onlyOwner {
        if (bytes(newName).length == 0) revert STR_EMPTY();
        if (bytes(newSymbol).length == 0) revert STR_EMPTY();
        if (bytes(newName).length > MAX_STRING_LENGTH) revert STR_TOO_LONG();
        if (bytes(newSymbol).length > MAX_STRING_LENGTH) revert STR_TOO_LONG();
        
        _name = newName;
        _symbol = newSymbol;
        
        emit NameSymbolUpdated(newName, newSymbol);
    }


    /**
     * @notice Configures anti-dump protection to prevent large sudden sells.
     * @dev Anti-dump protection limits the maximum percentage of total supply
     *      that can be sold in a single transaction and enforces a cooldown
     *      between large sells to prevent market manipulation.
     *      Reverts with DUMP_PERCENT if percentage is 0 or exceeds MAX_ANTI_DUMP_PERCENT,
     *      or CD_TOO_HIGH if cooldown exceeds MAX_ANTI_DUMP_COOLDOWN.
     * @param enabled True to activate anti-dump protection, false to disable
     * @param maxPercentage Maximum % of total supply allowed per sell (in basis points)
     * @param cooldownTime Required seconds to wait between large sells
     * @custom:access Only callable by contract owner
     * @custom:protection Prevents whale dumps that could crash token price
     * @custom:emit AntiDumpConfigUpdated event with all three parameters
     */
    function setAntiDumpConfig(bool enabled, uint256 maxPercentage, uint256 cooldownTime) external onlyOwner {
        if (maxPercentage == 0 || maxPercentage > MAX_ANTI_DUMP_PERCENT) revert DUMP_PERCENT();
        if (cooldownTime > MAX_ANTI_DUMP_COOLDOWN) revert CD_TOO_HIGH();
        antiDumpEnabled = enabled;
        maxSellPercentage = maxPercentage;
        sellCooldown = cooldownTime;
        emit AntiDumpConfigUpdated(enabled, maxPercentage, cooldownTime);
    }
    
    /**
     * @notice Configures maximum allowed price impact for DEX sells.
     * @dev Price impact protection prevents trades that would move the market
     *      price by more than the specified percentage. Calculated using AMM
     *      constant product formula. Impact is measured in basis points.
     *      Reverts with PRICE_MIN_IMPACT if enabled and below minimum,
     *      or PRICE_INVALID if exceeds BASIS_POINTS (100%).
     * @param enabled True to activate price impact limits, false to disable
     * @param maxImpactBasisPoints Maximum allowed price impact (e.g., 500 = 5%)
     * @custom:access Only callable by contract owner
     * @custom:calculation Uses constant product formula: (x+dx)(y-dy) = xy
     * @custom:protection Prevents trades that cause excessive price slippage
     * @custom:emit PriceImpactLimitConfigUpdated event
     */
    function setPriceImpactLimitConfig(bool enabled, uint256 maxImpactBasisPoints) external onlyOwner {
        if (enabled && maxImpactBasisPoints < MIN_PRICE_IMPACT_BPS) revert PRICE_MIN_IMPACT();
        if (maxImpactBasisPoints > BASIS_POINTS) revert PRICE_INVALID();
        priceImpactLimitEnabled = enabled;
        maxPriceImpactPercent = maxImpactBasisPoints;
        emit PriceImpactLimitConfigUpdated(enabled, maxImpactBasisPoints);
    }
    
    /**
     * @notice Sets whether an address is exempt from price impact protection.
     * @dev Exempt addresses can execute trades of any size regardless of price impact.
     *      Typically used for liquidity management contracts or authorized market makers.
     *      Reverts with ADDR_INVALID if account is zero address.
     * @param account The address to update exemption status for (cannot be zero)
     * @param exempt True to exempt from price impact limits, false to apply limits
     * @custom:access Only callable by contract owner
     * @custom:usage Typically granted to liquidity managers or trusted contracts
     * @custom:emit PriceImpactExemptUpdated event
     */
    function setPriceImpactExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        priceImpactExempt[account] = exempt;
        emit PriceImpactExemptUpdated(account, exempt);
    }
    
    /**
     * @notice Configures wallet cooldown protection between consecutive transactions.
     * @dev Cooldown protection enforces a minimum time delay between transactions
     *      from the same wallet to prevent rapid-fire trading and bot manipulation.
     *      Reverts with CD_TOO_HIGH if cooldown exceeds MAX_COOLDOWN.
     * @param enabled True to activate wallet cooldown checks, false to disable
     * @param cooldownSeconds Minimum seconds required between transactions per wallet
     * @custom:access Only callable by contract owner
     * @custom:protection Prevents rapid bot trading and front-running attacks
     * @custom:emit WalletCooldownConfigUpdated event
     */
    function setWalletCooldownConfig(bool enabled, uint256 cooldownSeconds) external onlyOwner {
        if (cooldownSeconds > MAX_COOLDOWN) revert CD_TOO_HIGH();
        walletCooldownEnabled = enabled;
        globalCooldownSeconds = cooldownSeconds;
        emit WalletCooldownConfigUpdated(enabled, cooldownSeconds);
    }
    
    /**
     * @notice Emergency function to withdraw stuck ERC20 tokens from this contract.
     * @dev Allows owner to recover any ERC20 tokens (including NTE itself) that are
     *      accidentally sent to the contract or stuck due to protocol issues.
     *      Uses low-level call to handle non-standard ERC20 tokens that don't
     *      return bool values. Validates return data when present.
     *      Reverts with EMG_INVALID_TOKEN if token is zero address,
     *      EMG_ZERO_RECIP if recipient is zero, EMG_INSUF_BAL if insufficient balance,
     *      or EMG_TRANSFER_FAIL if transfer fails.
     * @param token The address of the ERC20 token to withdraw (can be NTE or any other token)
     * @param to The recipient address for withdrawn tokens (cannot be zero)
     * @param amount The amount of tokens to withdraw (in token's base units)
     * @custom:access Only callable by contract owner with nonReentrant protection
     * @custom:safety Low-level call handles both standard and non-standard ERC20s
     * @custom:emit EmergencyTokenWithdraw event
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0)) revert EMG_INVALID_TOKEN();
        if (to == address(0)) revert EMG_ZERO_RECIP();
        
        // Check contract has sufficient balance
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < amount) revert EMG_INSUF_BAL();
        
        // Use low-level call to handle non-standard ERC20 tokens
        bytes memory payload = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        (bool success, bytes memory returndata) = token.call(payload);
        
        // Handle tokens that don't return a value or return false
        if (!success) revert EMG_TRANSFER_FAIL();
        if (returndata.length > 0) {
            if (!abi.decode(returndata, (bool))) revert EMG_TRANSFER_FAIL();
        }
        
        emit EmergencyTokenWithdraw(token, to, amount);
    }
    
    /**
     * @notice Emergency function to withdraw BNB/native currency from this contract.
     * @dev Allows owner to recover BNB that was sent to the contract (e.g., from
     *      liquidity operations or accidental sends). Safety restriction requires
     *      waiting 30 days after launch (OWNERSHIP_LOCK_PERIOD) to prevent abuse.
     *      Reverts with EMG_WAIT_30D if called before 30-day period,
     *      EMG_INVALID_RECIP if recipient is zero address,
     *      or EMG_INSUF_BAL_BNB if contract has insufficient balance.
     * @param to The recipient address for withdrawn BNB (payable, cannot be zero)
     * @param amount The amount of BNB to withdraw in wei (must not exceed contract balance)
     * @custom:access Only callable by contract owner with nonReentrant protection
     * @custom:security 30-day timelock prevents immediate withdrawal after launch
     * @custom:emit EmergencyBNBWithdraw event
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert EMG_WAIT_30D();
        if (to == address(0)) revert EMG_INVALID_RECIP();
        if (amount > address(this).balance) revert EMG_INSUF_BAL_BNB();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert EMG_BNB_FAIL();
        
        emit EmergencyBNBWithdraw(to, amount);
    }

    /**
     * @notice Configures MEV (Miner Extractable Value) protection settings.
     * @dev MEV protection prevents sandwich attacks and block manipulation by limiting\n     *      how frequently an address can trade. Two independent checks:\n     *      1. Block-based: Prevents trading in consecutive blocks (maxBlocks)\n     *      2. Time-based: Enforces minimum seconds between trades (minTime)\n     *      At least one parameter must be non-zero when enabling protection.\n     *      Reverts with MEV_CONFIG_INVALID if both are 0 when enabled,\n     *      MEV_BLOCKS_HIGH if maxBlocks exceeds MAX_MEV_BLOCKS,\n     *      or MEV_TIME_HIGH if minTime exceeds MAX_MEV_MIN_TIME.\n     * @param enabled True to activate MEV protection, false to disable\n     * @param maxBlocks Max blocks allowed between trades (0 = disabled, typical: 2-5)\n     * @param minTime Min seconds required between trades (0 = disabled, typical: 3-30)\n     * @custom:access Only callable by contract owner\n     * @custom:protection Prevents sandwich attacks, front-running, and block manipulation\n     * @custom:emit MevProtectionConfigured and optionally MevProtectionToggled events\n     */
    function setMevProtectionConfig(bool enabled, uint256 maxBlocks, uint256 minTime) external onlyOwner {
        // When enabling protection, at least one of the parameters must be non-zero
        if (enabled && maxBlocks == 0 && minTime == 0) revert MEV_CONFIG_INVALID();
        if (maxBlocks > MAX_MEV_BLOCKS) revert MEV_BLOCKS_HIGH();
        if (minTime > MAX_MEV_MIN_TIME) revert MEV_TIME_HIGH();

        bool previous = mevProtectionEnabled;
        mevProtectionEnabled = enabled;
        maxBlocksForMevProtection = maxBlocks;
        minTimeBetweenTxs = minTime;
        emit MevProtectionConfigured(enabled, maxBlocks, minTime);
        if (previous != enabled) {
            emit MevProtectionToggled(enabled);
        }
    }

    /**
     * @notice Sets the MEV protection exemption status for a specific address.
     * @dev MEV-exempt addresses can trade in consecutive blocks without triggering
     *      MEV protection revert. Typically granted to trusted contracts like
     *      DEX routers, aggregators, and protocol-owned liquidity managers.
     *      Reverts with ADDR_INVALID if account is zero address.
     * @param account The address to grant or revoke MEV exemption (cannot be zero)
     * @param exempt True to bypass MEV checks, false to apply MEV protection
     * @custom:access Only callable by contract owner
     * @custom:protection MEV protection prevents sandwich attacks and block manipulation
     * @custom:usage Grant to: routers, aggregators, trusted DeFi protocols
     * @custom:emit MevProtectionExemptUpdated event
     */
    function setMevProtectionExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        mevProtectionExempt[account] = exempt;
        emit MevProtectionExemptUpdated(account, exempt);
    }
    
    /**
     * @notice Configures transaction velocity protection to prevent rapid-fire trading.
     * @dev Velocity protection limits how many transactions an address can execute
     *      within a rolling time window (circular buffer of MAX_VELOCITY_BUFFER = 10).
     *      This prevents bot attacks, rapid dumping, and automated manipulation.
     *      Reverts with VEL_CONFIG_INVALID if enabled with maxTx or timeWindow = 0,
     *      or VEL_LIMIT_HIGH if maxTx exceeds buffer size or timeWindow too large.
     * @param enabled True to activate velocity limits, false to disable
     * @param maxTx Maximum allowed transactions per time window (max 10, buffer size limit)
     * @param timeWindow Duration of rolling window in seconds (e.g., 300 = 5 minutes)
     * @custom:access Only callable by contract owner
     * @custom:mechanism Uses circular buffer to track last 10 transaction timestamps
     * @custom:protection Prevents bot spam, rapid dumps, and automated manipulation
     * @custom:emit VelocityLimitConfigured event
     */
    function setVelocityLimitConfig(bool enabled, uint256 maxTx, uint256 timeWindow) external onlyOwner {
        if (enabled) {
            if (maxTx == 0 || timeWindow == 0) revert VEL_CONFIG_INVALID();
            if (maxTx > MAX_VELOCITY_BUFFER) revert VEL_LIMIT_HIGH();
            if (timeWindow > MAX_COOLDOWN) revert VEL_LIMIT_HIGH();
        }
        velocityLimitEnabled = enabled;
        maxTxPerWindow = maxTx;
        velocityTimeWindow = timeWindow;
        emit VelocityLimitConfigured(enabled, maxTx, timeWindow);
    }
    
    /**
     * @notice Sets the velocity protection exemption status for a specific address.
     * @dev Velocity-exempt addresses can execute unlimited transactions within time window.
     *      Typically granted to DEX routers, aggregators, and trusted protocol contracts
     *      that need to perform multiple operations without hitting rate limits.
     *      Reverts with ADDR_INVALID if account is zero address.
     * @param account The address to grant or revoke velocity exemption (cannot be zero)
     * @param exempt True to bypass velocity limits, false to apply transaction limits
     * @custom:access Only callable by contract owner
     * @custom:protection Velocity limits prevent bot spam and rapid manipulation
     * @custom:usage Grant to: routers, aggregators, liquidity managers
     * @custom:emit VelocityLimitExemptUpdated event
     */
    function setVelocityLimitExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        velocityLimitExempt[account] = exempt;
        emit VelocityLimitExemptUpdated(account, exempt);
    }

    /**
     * @notice Sets whether a helper contract can bypass trading protections for self-transfers.
     * @dev Bypass only applies when msg.sender == from inside _transferWithTax,
     *      meaning the helper is transferring its own tokens. This enables helper
     *      contracts (like category helpers) to operate smoothly without hitting
     *      velocity/MEV limits while moving their own funds.
     *      Reverts with ADDR_INVALID if helper is zero address,
     *      or ADDR_NOT_CONTRACT if enabling bypass for non-contract address.
     * @param helper The helper contract address to configure (must be a contract when enabling)
     * @param enabled True to allow bypass of protections, false to apply all protections
     * @custom:access Only callable by contract owner
     * @custom:security Bypass only works for self-transfers (helper moving its own tokens)
     * @custom:usage Typically used for category helper and liquidity manager contracts
     * @custom:emit HelperBypassUpdated event
     */
    function setHelperBypass(address helper, bool enabled) external onlyOwner {
        if (helper == address(0)) revert ADDR_INVALID();
        if (enabled && !_isContract(helper)) revert ADDR_NOT_CONTRACT();
        helperBypass[helper] = enabled;
        emit HelperBypassUpdated(helper, enabled);
    }

    /**
     * @notice Returns whether an address is exempt from transaction taxes.
     * @dev Tax-exempt addresses don't pay buy/sell/transfer taxes.
     *      Typically granted to DEX routers, liquidity managers, and protocol contracts.
     * @param account The address to query exemption status
     * @return exempt True if address is exempt from all taxes, false otherwise
     * @custom:view Read-only function with no state changes
     */
    function isTaxExempt(address account) external view returns (bool) {
        return taxExempt[account];
    }

    /**
     * @notice Returns whether an address is exempt from MEV protection checks.
     * @dev MEV-exempt addresses can trade in consecutive blocks without restrictions.
     *      Typically granted to trusted contracts and liquidity management systems.
     * @param account The address to query MEV exemption status
     * @return exempt True if address bypasses MEV protection, false otherwise
     * @custom:view Read-only function with no state changes
     */
    function isMevProtectionExempt(address account) external view returns (bool) {
        return mevProtectionExempt[account];
    }

    /**
     * @notice Returns whether an address is exempt from velocity limit checks.
     * @dev Velocity-exempt addresses can execute unlimited transactions within time window.
     *      Typically granted to DEX routers, aggregators, and trusted protocol contracts.
     * @param account The address to query velocity exemption status
     * @return exempt True if address bypasses velocity limits, false otherwise
     * @custom:view Read-only function with no state changes
     */
    function isVelocityLimitExempt(address account) external view returns (bool) {
        return velocityLimitExempt[account];
    }

    /**
     * @notice Returns a comprehensive snapshot of all MEV and velocity protection settings.
     * @dev Aggregates both MEV and velocity protection configurations in a single call
     *      for efficient frontend/dashboard integration. This is a gas-efficient way
     *      to fetch all protection parameters without multiple contract calls.
     *      
     *      **MEV Protection (Sandwich Attack Prevention):**
     *      - Block-based: maxBlocks = 0 disables, typical values: 2-5 blocks
     *      - Time-based: minTime = 0 disables, typical values: 3-30 seconds
     *      
     *      **Velocity Protection (Rate Limiting):**
     *      - Transaction limit: maxTx = max transactions in rolling window (1-10)
     *      - Time window: Duration for counting transactions (e.g., 300s = 5 min)
     * @return mevEnabled True if MEV protection is currently active
     * @return maxBlocks Maximum blocks allowed between trades (0 = disabled)
     * @return minTime Minimum seconds required between trades (0 = disabled)
     * @return velocityEnabled True if velocity limits are currently active
     * @return maxTx Maximum transactions allowed within time window
     * @return timeWindow Rolling window duration in seconds for velocity checks
     * @custom:view Read-only aggregation function with no state changes
     * @custom:usage Ideal for dashboards, monitoring tools, and frontend protection displays
     * @custom:protection Shows complete anti-bot and anti-manipulation configuration
     */
    function getProtectionConfig() external view returns (
        bool mevEnabled,
        uint256 maxBlocks,
        uint256 minTime,
        bool velocityEnabled,
        uint256 maxTx,
        uint256 timeWindow
    ) {
        return (
            mevProtectionEnabled,
            maxBlocksForMevProtection,
            minTimeBetweenTxs,
            velocityLimitEnabled,
            maxTxPerWindow,
            velocityTimeWindow
        );
    }
    
    /**
     * @notice Checks if an address is currently blacklisted with an active (non-expired) restriction.
     * @dev Performs three checks to determine active blacklist status:
     *      1. Is address marked as blacklisted (isBlacklisted mapping)
     *      2. If expiry is 0, blacklist is permanent (returns true)
     *      3. If expiry is set, checks if current time is before expiry
     *      
     *      Returns false in these cases:
     *      - Address was never blacklisted
     *      - Blacklist has expired (current time >= expiry)
     *      - Blacklist was manually removed
     * @param account The address to check blacklist status for
     * @return isActive True if address is actively blacklisted (cannot trade), false otherwise
     * @custom:view Read-only function with no state modifications
     * @custom:expiry Temporary blacklists automatically become inactive after expiry timestamp
     * @custom:usage Check before transfers, display in UI, or for compliance verification
     */
    function isBlacklistedActive(address account) public view returns (bool) {
        if (!isBlacklisted[account]) return false;
        if (blacklistExpiry[account] == 0) return true; // Permanent restriction
        return block.timestamp < blacklistExpiry[account];
    }
    
    /**
     * @notice Public utility to remove expired blacklist entries and free storage.
     * @dev Anyone can call this function to clean up expired blacklist data.
     *      Performs gas-efficient cleanup by resetting both isBlacklisted flag
     *      and blacklistExpiry timestamp when an entry has expired.
     *      
     *      **Cleanup conditions (all must be true):**
     *      1. Address is marked as blacklisted
     *      2. Expiry timestamp is non-zero (not permanent)
     *      3. Current time >= expiry timestamp (has expired)
     *      
     *      Gas refund: Resetting storage to zero returns gas (SSTORE refund).
     *      Emits BlacklistUpdated event to notify off-chain systems.
     * @param account The address to clean up expired blacklist data for
     * @custom:public Anyone can call to trigger cleanup (permissionless)
     * @custom:gas Storage reset provides gas refund to caller
     * @custom:emit BlacklistUpdated event when cleanup occurs
     * @custom:usage Useful for keeping contract state clean and claiming gas refunds
     */
    function cleanExpiredBlacklist(address account) external {
        if (isBlacklisted[account] && blacklistExpiry[account] != 0 && block.timestamp >= blacklistExpiry[account]) {
            isBlacklisted[account] = false;
            blacklistExpiry[account] = 0;
            emit BlacklistUpdated(account, false);
        }
    }
    
    /**
     * @notice Checks if an address is currently whitelisted with an active (non-expired) permission.
     * @dev Performs three checks to determine active whitelist status:
     *      1. Is address marked as whitelisted (isWhitelisted mapping)
     *      2. If expiry is 0, whitelist is permanent (returns true)
     *      3. If expiry is set, checks if current time is before expiry
     *      
     *      Returns false in these cases:
     *      - Address was never whitelisted
     *      - Whitelist has expired (current time >= expiry)
     *      - Whitelist was manually removed
     *      
     *      Used during whitelist-only mode to grant trading permissions.
     * @param account The address to check whitelist status for
     * @return isActive True if address has active whitelist permission (can trade in whitelist mode), false otherwise
     * @custom:view Read-only function with no state modifications
     * @custom:expiry Temporary whitelists automatically become inactive after expiry timestamp
     * @custom:usage Check during transfers when whitelistEnabled is true
     */
    function isWhitelistedActive(address account) public view returns (bool) {
        if (!isWhitelisted[account]) return false;
        if (whitelistExpiry[account] == 0) return true; // Permanent permission
        return block.timestamp < whitelistExpiry[account];
    }
    
    /**
     * @notice Public utility to remove expired whitelist entries and free storage.
     * @dev Anyone can call this function to clean up expired whitelist data.
     *      Performs gas-efficient cleanup by resetting both isWhitelisted flag
     *      and whitelistExpiry timestamp when an entry has expired.
     *      
     *      **Cleanup conditions (all must be true):**
     *      1. Address is marked as whitelisted
     *      2. Expiry timestamp is non-zero (not permanent)
     *      3. Current time >= expiry timestamp (has expired)
     *      
     *      Gas refund: Resetting storage to zero returns gas (SSTORE refund).
     *      Emits WhitelistUpdated event to notify off-chain systems.
     * @param account The address to clean up expired whitelist data for
     * @custom:public Anyone can call to trigger cleanup (permissionless)
     * @custom:gas Storage reset provides gas refund to caller
     * @custom:emit WhitelistUpdated event when cleanup occurs
     * @custom:usage Useful for keeping contract state clean and claiming gas refunds
     */
    function cleanExpiredWhitelist(address account) external {
        if (isWhitelisted[account] && whitelistExpiry[account] != 0 && block.timestamp >= whitelistExpiry[account]) {
            isWhitelisted[account] = false;
            whitelistExpiry[account] = 0;
            emit WhitelistUpdated(account, false);
        }
    }

    /**
     * @notice Registers or unregisters a DEX pair address for proper tax application.
     * @dev DEX pairs are used to determine if a transfer is a buy/sell (taxed) or
     *      regular transfer (different tax rate). Add new pairs when creating
     *      liquidity on additional DEXes or chains to ensure proper tax collection.
     *      Prevents accidental removal of main pancakePair for safety.
     *      Reverts with ADDR_INVALID if pair is zero,
     *      DEX_PAIR_NOT_CONTRACT if not a contract,
     *      or DEX_PAIR_CHECK if trying to unregister main pair.
     * @param pair The liquidity pair contract address (must be a contract)
     * @param status True to register as DEX pair (apply buy/sell tax), false to unregister
     * @custom:access Only callable by contract owner
     * @custom:usage Add pairs for PancakeSwap, Uniswap, or other DEX liquidity pools
     * @custom:safety Cannot disable main pancakePair to prevent tax evasion
     * @custom:emit DexPairUpdated event
     */
    function setDexPairStatus(address pair, bool status) external onlyOwner {
        if (pair == address(0)) revert ADDR_INVALID();
        if (!_isContract(pair)) revert DEX_PAIR_NOT_CONTRACT();
        // Prevent accidentally disabling the main pancakePair
        if (pair == pancakePair && !status) revert DEX_PAIR_CHECK();
        isPancakePair[pair] = status;
        emit DexPairUpdated(pair, status);
    }

    /**
     * @notice Sets the PancakeSwap router address for DEX integration.
     * @dev Updates the stored PancakeSwap router used for AMM operations and pair detection.
     *      This provides a recovery mechanism if router wasn't properly set during deployment
     *      or needs to be updated to a new router version.
     *      Reverts with ADDR_ZERO if router is zero address,
     *      or DEX_ROUTER if address is not a contract.
     * @param _pancakeRouter The PancakeSwap router contract address (must be valid contract)
     * @custom:access Only callable by contract owner
     * @custom:usage Update when migrating to new DEX version or fixing deployment issues
     * @custom:emit PancakeRouterUpdated event
     */
    function setPancakeRouter(address _pancakeRouter) external onlyOwner {
        if (_pancakeRouter == address(0)) revert ADDR_ZERO();
        if (!_isContract(_pancakeRouter)) revert DEX_ROUTER();
        
        pancakeRouter = _pancakeRouter;
        emit PancakeRouterUpdated(_pancakeRouter);
    }

    /**
     * @notice Directly sets the primary PancakeSwap liquidity pair address.
     * @dev Updates the main trading pair for NTE/WBNB on PancakeSwap.
     *      Use this to manually configure the pair if automatic initialization failed
     *      during deployment or to update to a different pair version.
     *      Automatically unregisters old pair and registers new pair in isPancakePair mapping.
     *      Reverts with ADDR_ZERO if pair is zero address,
     *      or DEX_PAIR_NOT_CONTRACT if address is not a contract.
     * @param _pancakePair The liquidity pair contract address (must be valid contract)
     * @custom:access Only callable by contract owner
     * @custom:usage Manual pair setup or migration to new liquidity pool
     * @custom:effect Unregisters old pair and registers new pair automatically
     * @custom:emit PancakePairUpdated event
     */
    function setPancakePair(address _pancakePair) external onlyOwner {
        if (_pancakePair == address(0)) revert ADDR_ZERO();
        if (!_isContract(_pancakePair)) revert DEX_PAIR_NOT_CONTRACT();
        
        // Unregister old pair if it exists
        if (pancakePair != address(0)) {
            isPancakePair[pancakePair] = false;
        }
        
        pancakePair = _pancakePair;
        isPancakePair[_pancakePair] = true;
        emit PancakePairUpdated(_pancakePair);
    }

    /**
     * @notice Sets the authorized staking contract that can lock/unlock user balances.
     * @dev The staking contract is granted special privileges to lock tokens without
     *      transferring them, enabling users to stake while keeping tokens in their wallet.
     *      Safety check prevents changing staking contract if users have active locks.
     *      Reverts with ADDR_ZERO if contract is zero address,
     *      STAKING_NOT_CONTRACT if not a valid contract,
     *      or STAKING_ACTIVE_LOCKS if trying to change with existing locks.
     * @param _stakingContract The staking contract address (must be valid contract)
     * @custom:access Only callable by contract owner
     * @custom:security Cannot change if totalLockedForStaking > 0 (protects user funds)
     * @custom:integration Staking contract calls lockFromStaking/unlockFromStaking
     * @custom:emit StakingContractUpdated event
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        if (_stakingContract == address(0)) revert ADDR_ZERO();
        if (!_isContract(_stakingContract)) revert STAKING_NOT_CONTRACT();
        if (_stakingContract != stakingContract && totalLockedForStaking > 0) revert STAKING_ACTIVE_LOCKS();
        stakingContract = _stakingContract;
        
        emit StakingContractUpdated(_stakingContract);
    }

    /**
     * @notice Toggles whitelist enforcement for helper-bypass transfers.
     * @dev Controls whether helper contracts using bypass mode must still pass
     *      whitelist checks when whitelistEnabled is true. When enforcement is
     *      enabled, even helper bypass transfers must involve whitelisted addresses.
     *      When disabled, helper bypass transfers skip whitelist validation entirely.
     * @param enabled True to enforce whitelist on helper transfers, false to allow bypass
     * @custom:access Only callable by contract owner
     * @custom:conditional Only relevant when whitelistEnabled is true
     * @custom:emit HelperWhitelistEnforcementUpdated event
     */
    function setHelperWhitelistEnforcement(bool enabled) external onlyOwner {
        enforceWhitelistOnHelper = enabled;
        emit HelperWhitelistEnforcementUpdated(enabled);
    }

    /**
     * @notice Called exclusively by staking contract to lock tokens for a user.
     * @dev Locks tokens in-place without transferring them, preventing user from
     *      transferring locked amount while maintaining wallet balance visibility.
     *      Locked tokens still appear in balanceOf() but cannot be transferred.
     *      Reverts with AUTH_INVALID if caller is not the staking contract,
     *      ADDR_INVALID if user is zero address, TXN_AMOUNT_ZERO if amount is zero,
     *      or TXN_EXCEEDS_BAL if user doesn't have sufficient unlocked balance.
     * @param user The address whose tokens will be locked (cannot be zero)
     * @param amount The amount of tokens to lock (in base units with 18 decimals)
     * @custom:access ONLY callable by authorized stakingContract address
     * @custom:effects Increases lockedForStaking[user] and totalLockedForStaking
     * @custom:security User must have sufficient unlocked balance for the lock
     * @custom:emit TokensLockedForStaking event
     */
    function lockFromStaking(address user, uint256 amount) external {
        if (msg.sender != stakingContract) revert AUTH_INVALID();
        if (user == address(0)) revert ADDR_INVALID();
        if (amount == 0) revert TXN_AMOUNT_ZERO();
        uint256 balance = _balances[user];
        uint256 locked = lockedForStaking[user];
        if (balance < locked + amount) revert TXN_EXCEEDS_BAL();
        unchecked {
            lockedForStaking[user] = locked + amount;
        }
        totalLockedForStaking += amount;
        
        emit TokensLockedForStaking(user, amount);
    }

    /**
     * @notice Called exclusively by staking contract to unlock tokens for a user.
     * @dev Unlocks previously locked tokens, making them freely transferable again.
     *      This is called when user unstakes or claims rewards. Tokens never leave
     *      the user's wallet during the lock/unlock cycle.
     *      Reverts with AUTH_INVALID if caller is not the staking contract,
     *      ADDR_INVALID if user is zero address, TXN_AMOUNT_ZERO if amount is zero,
     *      or TXN_EXCEEDS_BAL if trying to unlock more than currently locked.
     * @param user The address whose tokens will be unlocked (cannot be zero)
     * @param amount The amount of tokens to unlock (in base units with 18 decimals)
     * @custom:access ONLY callable by authorized stakingContract address
     * @custom:effects Decreases lockedForStaking[user] and totalLockedForStaking
     * @custom:security Cannot unlock more than currently locked amount
     * @custom:emit TokensUnlockedFromStaking event
     */
    function unlockFromStaking(address user, uint256 amount) external {
        if (msg.sender != stakingContract) revert AUTH_INVALID();
        if (user == address(0)) revert ADDR_INVALID();
        if (amount == 0) revert TXN_AMOUNT_ZERO();
        uint256 locked = lockedForStaking[user];
        if (locked < amount) revert TXN_EXCEEDS_BAL();
        unchecked {
            lockedForStaking[user] = locked - amount;
        }
        totalLockedForStaking -= amount;
        
        emit TokensUnlockedFromStaking(user, amount);
    }

    /**
     * @notice Emergency function to unlock staking tokens if staking contract fails.
     * @dev Safety mechanism to recover locked tokens if staking contract becomes
     *      non-functional or malicious. Strict safety restrictions:
     *      - Can only be called 1 year (365 days) after launch
     *      - Only works if stakingContract is invalid or not a contract anymore
     *      This prevents abuse while providing ultimate recovery for users.
     *      Reverts with EMG_WAIT_1Y if called before 1-year period,
     *      or STAKING_ACTIVE_LOCKS if staking contract is still valid.
     * @param user The address whose locked tokens should be emergency unlocked
     * @custom:access Only callable by contract owner
     * @custom:security 1-year timelock + staking contract must be broken
     * @custom:emergency Last resort recovery if staking contract becomes unusable
     * @custom:emit TokensUnlockedFromStaking event
     */
    function emergencyUnlockStaking(address user) external onlyOwner {
        if (block.timestamp <= launchTime + 365 days) revert EMG_WAIT_1Y();
        if (stakingContract != address(0) && _isContract(stakingContract)) revert STAKING_ACTIVE_LOCKS();
        
        uint256 locked = lockedForStaking[user];
        if (locked > 0) {
            lockedForStaking[user] = 0;
            totalLockedForStaking -= locked;
            emit TokensUnlockedFromStaking(user, locked);
        }
    }

    // ============================================
    // INTERNAL STUFF - For Our Eyes Only
    // ============================================
    
    /**
     * @dev Internal function to mint new tokens and increase total supply.
     *      This function is used during initial deployment to create the token supply.
     *      Emits a {Transfer} event from the zero address to indicate token creation.
     * @param account The address that will receive the newly minted tokens
     * @param amount The amount of tokens to mint (in base units with 18 decimals)
     * @custom:security Validates account is not zero address before minting
     * @custom:effects Increases total supply and recipient balance by amount
     */
    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert MINT_TO_ZERO();
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    
    /**
     * @dev Internal function to permanently destroy tokens and decrease total supply.
     *      Burned tokens are moved to the zero address and tracked in totalBurned.
     *      Emits a {Transfer} event to the zero address to indicate token destruction.
     * @param account The address from which tokens will be burned
     * @param amount The amount of tokens to burn (in base units with 18 decimals)
     * @custom:security Validates account is not zero address and has sufficient balance
     * @custom:effects Decreases total supply, account balance, and increases totalBurned counter
     */
    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert BURN_FROM_ZERO();
        uint256 accountBalance = _balances[account];
        if (accountBalance < amount) revert BURN_EXCEEDS();
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
            totalBurned += amount;
        }
        emit Transfer(account, address(0), amount);
    }
    
    /**
     * @dev Core internal transfer function that moves tokens between addresses.
     *      This is a pure accounting function with no taxes, protections, or business logic.
     *      All security checks and tax calculations are handled by _transferWithTax.
     *      Emits a {Transfer} event to record the token movement on-chain.
     * @param from The address sending tokens (must not be zero and have sufficient balance)
     * @param to The address receiving tokens (must not be zero)
     * @param amount The amount of tokens to transfer (in base units with 18 decimals)
     * @custom:security Validates both addresses are non-zero and sender has sufficient balance
     * @custom:effects Decreases from balance and increases to balance by amount
     */
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ADDR_FROM_ZERO();
        if (to == address(0)) revert ADDR_TO_ZERO();
        
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert TXN_EXCEEDS_BAL();
        uint256 locked = lockedForStaking[from];
        if (fromBalance - amount < locked) revert TXN_EXCEEDS_BAL();
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @dev Internal function to set spending allowance for delegated token transfers.
     *      Implements the ERC20 approval mechanism allowing smart contracts and other
     *      addresses to spend tokens on behalf of the owner. Emits an {Approval} event.
     * @param tokenOwner The address that owns the tokens and grants permission
     * @param spender The address that will be allowed to spend the tokens
     * @param amount The maximum amount of tokens the spender can transfer
     * @custom:security Validates both owner and spender addresses are non-zero
     */
    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        if (tokenOwner == address(0)) revert APRV_FROM_ZERO();
        if (spender == address(0)) revert APRV_TO_ZERO();
        _allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }

    /**
     * @notice Increases the allowance granted to a spender by a specific amount.
     * @dev Safer alternative to calling approve() directly, prevents front-running issues.
     *      Adds to existing allowance rather than replacing it. This avoids the race
     *      condition where a spender could potentially spend both old and new allowance.
     *      Reverts with APRV_OVERFLOW if addition would overflow uint256.
     * @param spender The address whose allowance will be increased (typically a contract)
     * @param addedValue The additional amount to add to current allowance
     * @return success Always returns true on successful allowance increase
     * @custom:security Prevents front-running attacks possible with approve()
     * @custom:recommended Preferred over approve() for increasing allowances
     * @custom:emit Approval event with new total allowance
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance + addedValue < currentAllowance) revert APRV_OVERFLOW();
        _approve(msg.sender, spender, currentAllowance + addedValue);
        return true;
    }
    
    /**
     * @dev Private function to enforce velocity limits on trading frequency.
     *      Uses a circular buffer to track timestamps of recent transactions and ensures
     *      the account hasn't exceeded maxTxPerWindow within velocityTimeWindow period.
     * @param account The address whose trading velocity is being checked
     * @custom:gas Uses circular buffer with MAX_VELOCITY_BUFFER (10) to minimize costs
     */
    function _checkVelocityLimit(address account) private {
        uint256 currentTime = block.timestamp;
        uint256 window = velocityTimeWindow;
        uint256 maxTx = maxTxPerWindow;
        
        // Let's count how many trades happened in the window
        uint256 txCount = 0;
        for (uint256 i = 0; i < MAX_VELOCITY_BUFFER; i++) {
            uint256 txTime = userVelocityBuffer[account][i];
            if (txTime != 0 && currentTime - txTime <= window) {
                txCount++;
            }
        }
        
        // Reached the limit? Block the trade.
        if (txCount >= maxTx) {
            emit VelocityLimitTriggered(account, txCount, window);
            revert MEV_VELOCITY();
        }
        
        // Save the timestamp and move to the next slot in the buffer
        uint256 index = userVelocityIndex[account];
        userVelocityBuffer[account][index] = currentTime;
        userVelocityIndex[account] = (index + 1) % MAX_VELOCITY_BUFFER;
    }

    /**
     * @notice Decreases the allowance granted to a spender by a specific amount.
     * @dev Safer alternative to calling approve() directly, prevents front-running issues.
     *      Subtracts from existing allowance rather than replacing it. Useful for
     *      partially revoking permissions or correcting over-approvals.
     *      Reverts with APRV_UNDERFLOW if subtraction would underflow (insufficient allowance).
     * @param spender The address whose allowance will be decreased (typically a contract)
     * @param subtractedValue The amount to subtract from current allowance
     * @return success Always returns true on successful allowance decrease
     * @custom:security Prevents front-running attacks possible with approve()
     * @custom:recommended Preferred over approve() for decreasing allowances
     * @custom:emit Approval event with new reduced allowance
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance < subtractedValue) revert APRV_UNDERFLOW();
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }
    
    /**
     * @dev Internal function to validate and consume spending allowance for transferFrom operations.
     *      Checks if spender has sufficient allowance from account to spend amount tokens.
     *      Infinite allowance (type(uint256).max) is never decreased for gas efficiency.
     *      Decreases allowance by amount if not infinite, preventing overspending.
     *      Reverts with APRV_INSUFFICIENT if spender doesn't have enough allowance.
     * @param account The token owner whose allowance is being checked (grants permission)
     * @param spender The address attempting to spend tokens (must have allowance)
     * @param amount The number of tokens being spent (must not exceed allowance)
     * @custom:security Validates allowance before transfer, prevents unauthorized spending
     * @custom:optimization Infinite allowance (max uint256) never decreases (gas efficient)
     * @custom:usage Called by transferFrom and transactionFrom before executing transfer
     */
    function _spendAllowance(address account, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(account, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert APRV_INSUFFICIENT();
            unchecked {
                _approve(account, spender, currentAllowance - amount);
            }
        }
    }
    
    /**
     * @dev Internal function to update trading state timestamps for protection mechanisms.
     *      This records the block number and timestamp of the most recent trade for an account,
     *      which is used by MEV protection, velocity limits, and cooldown enforcement.
     * @param account The address whose trading state is being updated
     * @custom:effects Updates lastBlockNumber and lastTradeTime mappings for the account
     * @custom:usage Called after every successful transfer in _transferWithTax
     */
    function _updateTradingState(address account) internal {
        lastBlockNumber[account] = block.number;
        lastTradeTime[account] = block.timestamp;
    }

    /**
     * @dev Core internal transfer engine with comprehensive tax collection and protection enforcement.
     *      This is the heart of NTE's security architecture, executing all transfers through a
     *      multi-layered validation and protection system before token movement occurs.
     *      
     *      **Execution Flow (in order):**
     *      1. **Basic Validation**: Zero address checks, amount validation
     *      2. **Helper Bypass Detection**: Checks if msg.sender is authorized helper doing self-transfer
     *      3. **Pause Check**: Blocks transfers if paused (owner exemption optional)
     *      4. **Helper Bypass Path**: If helper bypass active, apply only blacklist/whitelist checks, skip protections
     *      5. **Anti-Bot Launch Protection**: Blocks non-exempt addresses during initial launch period
     *      6. **Blacklist Enforcement**: Prevents transfers involving blacklisted addresses
     *      7. **Whitelist Enforcement**: Requires whitelist permission when whitelistEnabled is true
     *      8. **Velocity Limit Check**: Prevents rapid-fire transactions exceeding configured limits
     *      9. **MEV Protection**: Multi-layer sandwich attack and bot prevention:
     *         - Blocks contracts from selling directly to pairs
     *         - Blocks brand new wallets (lastBlockNumber == 0) from selling
     *         - Enforces 60-second hold period before selling (MIN_HOLD_BEFORE_SELL)
     *         - Block-based protection (maxBlocksForMevProtection)
     *         - Time-based protection (minTimeBetweenTxs)
     *      10. **Wallet Cooldown**: Enforces minimum time between transactions per wallet
     *      11. **Price Impact Limit**: Prevents trades that would move market price too much
     *      12. **Anti-Dump Protection**: Enforces max sell percentage and cooldown between large sells
     *      13. **Trading State Update**: Records block number and timestamp for protection tracking
     *      14. **Tax Calculation & Routing**:
     *          - Tax-exempt addresses bypass tax collection
     *          - Calculate buy/sell/transfer tax based on transaction type
     *          - Split tax between treasury and liquidity collector (if auto-liquidity enabled)
     *          - Execute transfers with tax deduction
     *          - Emit routing events for transparency
     *      
     *      **Tax Routing Logic:**
     *      When autoLiquidityEnabled is true:
     *      - liquidityAmount = tax * (autoLiquidityBps / BASIS_POINTS)
     *      - treasuryAmount = tax - liquidityAmount
     *      Otherwise all tax goes to treasury.
     *      
     *      **Revert Conditions:**
     *      Reverts with various custom errors for validation failures:
     *      TXN_AMOUNT_ZERO, ADDR_FROM_ZERO, ADDR_TO_ZERO, SYS_DISABLED, BL_SENDER,
     *      BL_RECIPIENT, WL_REQUIRED, SEC_BOT_ACTIVE, MEV_VELOCITY, MEV_TOO_FAST,
     *      CD_SENDER, CD_RECIPIENT, CD_SELL, PRICE_TOO_HIGH, DUMP_EXCEEDS,
     *      TAX_TREASURY_ZERO, TXN_TAX_MISMATCH
     * @param from The token sender address (wallet or contract)
     * @param to The token recipient address (wallet, contract, or DEX pair)
     * @param amount The total token amount being transferred (before tax deduction)
     * @custom:reentrancy Protected by nonReentrant modifier to prevent reentrancy attacks
     * @custom:security Multi-layered protection system with 13+ validation checkpoints
     * @custom:emissions Emits Transfer events for all token movements, plus TaxRouted and LiquidityRouted
     * @custom:optimization Caches timestamps before checks to prevent repeated storage reads
     */
    function _transferWithTax(address from, address to, uint256 amount) internal nonReentrant {
        // Basic checks first
        if (amount == 0) revert TXN_AMOUNT_ZERO();
        if (from == address(0)) revert ADDR_FROM_ZERO();
        if (to == address(0)) revert ADDR_TO_ZERO();
        bool isHelperBypassFlow = (helperBypass[msg.sender] && from == msg.sender);
        
        // If we're paused, everything stops (unless you're the owner)
        if (_paused) {
            if (pauseIncludesOwner) {
                revert SYS_DISABLED();
            } else {
                if (from != _owner && to != _owner && msg.sender != _owner) revert SYS_DISABLED();
            }
        }

        // Owner-approved helper self-transfers should not be throttled/taxed by
        // trading protections. Keep pause and blacklist checks as global controls.
        if (isHelperBypassFlow) {
            if (isBlacklistedActive(from)) revert BL_SENDER();
            if (isBlacklistedActive(to)) revert BL_RECIPIENT();
            if (isBlacklistedActive(msg.sender) && msg.sender != from) revert BL_SENDER();

            // Optional whitelist enforcement for helper-bypass transfers.
            if (whitelistEnabled && enforceWhitelistOnHelper) {
                if (!(from == _owner || to == _owner || msg.sender == _owner ||
                    isWhitelistedActive(from) || isWhitelistedActive(to) || isWhitelistedActive(msg.sender) ||
                    from == address(this) || to == address(this))) {
                    revert WL_REQUIRED();
                }
            }
            _transfer(from, to, amount);
            return;
        }
        
        // Launch day shields - very strict for the first hour or so
        if (antiBotEnabled && block.timestamp < launchTime + antiBotDuration) {
            if (!(from == _owner || to == _owner || msg.sender == _owner || taxExempt[from] || taxExempt[to] || taxExempt[msg.sender])) {
                revert SEC_BOT_ACTIVE();
            }
        }
        
        if (isBlacklistedActive(from)) revert BL_SENDER();
        if (isBlacklistedActive(to)) revert BL_RECIPIENT();
        if (isBlacklistedActive(msg.sender) && msg.sender != from) revert BL_SENDER();
        
        if (whitelistEnabled) {
            if (!(from == _owner || to == _owner || msg.sender == _owner ||
                isWhitelistedActive(from) || isWhitelistedActive(to) || isWhitelistedActive(msg.sender) ||
                from == address(this) || to == address(this))) {
                revert WL_REQUIRED();
            }
        }
        
        if (velocityLimitEnabled && !velocityLimitExempt[from] && from != _owner && from != address(this)) {
            _checkVelocityLimit(from);
        }
        
        // Capture the old timestamps BEFORE we update them for the current trade
        uint256 cachedFromLastTrade = lastTradeTime[from];
        uint256 cachedToLastTrade = lastTradeTime[to];
        
        // MEV Protection - spotting bots and fresh wallets trying to dump
        if (mevProtectionEnabled && !mevProtectionExempt[from] && !mevProtectionExempt[to]) {
            bool isSellToPair = isPancakePair[to];
            
            // Check if it's a contract (robots usually live in contracts)
            bool isFromContract = _isContract(from);
            
            // Contracts can't sell directly to the pool (stops flash loan attacks)
            if (isSellToPair && isFromContract && from != address(this)) {
                emit MevAttackPrevented(from, block.number, "Contract selling to pair");
                revert MEV_VELOCITY();
            }
            
            // If it's a sell, we check if the wallet is brand new
            if (isSellToPair) {
                if (lastBlockNumber[from] == 0) {
                    emit MevAttackPrevented(from, block.number, "Brand new wallet");
                    revert MEV_VELOCITY();
                }
                // Even if not brand new, you can't sell if you just bought 60 seconds ago
                if (lastTradeTime[from] != 0 && block.timestamp - lastTradeTime[from] < MIN_HOLD_BEFORE_SELL) {
                    emit MevAttackPrevented(from, block.number, "Too soon after buy");
                    revert MEV_VELOCITY();
                }
            }
            
            // General speed checks for everyone else
            if (lastBlockNumber[from] != 0) {
                if (block.number > lastBlockNumber[from]) {
                    if ((block.number - lastBlockNumber[from]) <= maxBlocksForMevProtection) {
                        emit MevAttackPrevented(from, block.number, "Too soon");
                        revert MEV_VELOCITY();
                    }
                }
                
                if ((block.timestamp - lastTradeTime[from]) < minTimeBetweenTxs) {
                    emit MevAttackPrevented(from, block.number, "Too fast");
                    revert MEV_TOO_FAST();
                }
            }
        }
        
        bool isToPair = isPancakePair[to];
        
        // Cooldown checks - did you wait long enough since your last move?
        if (walletCooldownEnabled) {
            if (cachedFromLastTrade != 0 && block.timestamp < cachedFromLastTrade + globalCooldownSeconds) revert CD_SENDER();
            
            if (!isToPair && to != address(this)) {
                if (cachedToLastTrade != 0 && block.timestamp < cachedToLastTrade + globalCooldownSeconds) revert CD_RECIPIENT();
            }
        }
        
        if (priceImpactLimitEnabled && isToPair && !priceImpactExempt[from] && pancakeRouter != address(0)) {
            uint256 priceImpact = _calculatePriceImpact(amount, to);
            if (priceImpact > maxPriceImpactPercent) revert PRICE_TOO_HIGH();
        }
        
        // Anti-dump - preventing massive sells that crash the price
        if (antiDumpEnabled && isToPair && !taxExempt[from]) {
            uint256 maxSellAmount = (_totalSupply * maxSellPercentage) / BASIS_POINTS;
            if (amount > maxSellAmount) revert DUMP_EXCEEDS();
            
            if (cachedFromLastTrade != 0 && block.timestamp < cachedFromLastTrade + sellCooldown) revert CD_SELL();
        }
        
        // Now that we're sure the trade is legit, update the state
        _updateTradingState(from);
        if (!isToPair && to != address(this)) {
            _updateTradingState(to);
        }
        
        // Final step: Move the tokens (and take tax if applicable)
        if (
            from == _owner ||
            to == _owner ||
            from == address(this) ||
            to == address(this) ||
            taxExempt[from] ||
            taxExempt[to]
        ) {
            _transfer(from, to, amount);
        } else {
            uint256 tax = _calculateTax(from, to, amount);
            
            if (tax > 0) {
                if (treasury == address(0)) revert TAX_TREASURY_ZERO();
                
                uint256 afterTax = amount - tax;

                uint256 liquidityAmount = 0;
                uint256 treasuryAmount = tax;

                if (
                    autoLiquidityEnabled &&
                    liquidityCollector != address(0) &&
                    autoLiquidityBps > 0
                ) {
                    liquidityAmount = (tax * autoLiquidityBps) / BASIS_POINTS;
                    treasuryAmount = tax - liquidityAmount;
                }
                
                _transfer(from, to, afterTax);

                if (liquidityAmount > 0) {
                    _transfer(from, liquidityCollector, liquidityAmount);
                    emit LiquidityRouted(from, liquidityCollector, liquidityAmount);
                }

                if (treasuryAmount > 0) {
                    _transfer(from, treasury, treasuryAmount);
                    emit TaxRouted(from, treasury, treasuryAmount);
                }
                
                if (afterTax + liquidityAmount + treasuryAmount != amount) revert TXN_TAX_MISMATCH();
            } else {
                _transfer(from, to, amount);
            }
        }
    }

    /**
     * @dev Internal function to determine applicable tax rate and calculate tax amount for a transfer.
     *      Analyzes transaction type by examining sender and recipient addresses against DEX pair
     *      registry to classify as buy, sell, arbitrage, or peer-to-peer transfer.
     *      
     *      **Tax Classification Logic:**
     *      1. **Buy**: DEX pair → user wallet = buyTaxBps (e.g., 200 = 2%)
     *      2. **Sell**: user wallet → DEX pair = sellTaxBps (e.g., 200 = 2%)
     *      3. **Arbitrage**: DEX pair → DEX pair = sellTaxBps (higher tax on arb bots)
     *      4. **P2P Transfer**: wallet → wallet = transferTaxBps (e.g., 300 = 3%)
     *      5. **Router Transactions**: Excludes router to prevent double taxation during swaps
     *      
     *      **Special Cases:**
     *      - Router as from/to: Returns 0 tax to avoid double taxation on DEX operations
     *      - Tax rate 0: Returns 0 immediately (no tax applied)
     *      - Overflow protection: Validates multiplication won't overflow before calculation
     *      
     *      **Formula:**
     *      taxAmount = (amount × taxBps) / BASIS_POINTS
     *      Where BASIS_POINTS = 10000, so 200 bps = 2%
     *      
     *      Reverts with TXN_OVERFLOW if amount × taxBps would overflow uint256.
     * @param from Sender address (checked against isPancakePair and pancakeRouter)
     * @param to Recipient address (checked against isPancakePair and pancakeRouter)
     * @param amount Base transfer amount before tax deduction (in token base units with 18 decimals)
     * @return taxAmount The calculated tax amount in tokens (0 if no tax applicable)
     * @custom:classification Uses isPancakePair mapping to identify DEX transactions
     * @custom:safety Overflow protection prevents arithmetic overflow on large amounts
     * @custom:precision Uses basis points for sub-percent tax precision (0.01% increments)
     */
    function _calculateTax(address from, address to, uint256 amount) private view returns (uint256) {
        uint256 taxBps = 0;
        
        if (isPancakePair[from] && !isPancakePair[to]) {
            // Buy: from DEX to user
            taxBps = buyTaxBps;
        } else if (!isPancakePair[from] && isPancakePair[to]) {
            // Sell: from user to DEX
            taxBps = sellTaxBps;
        } else if (isPancakePair[from] && isPancakePair[to]) {
            // Pool-to-pool move (usually arbitrage)
            taxBps = sellTaxBps;
        } else if (pancakeRouter != from && pancakeRouter != to) {
            // Regular P2P transfer (exclude router to prevent double taxation)
            taxBps = transferTaxBps;
        }
        
        if (taxBps == 0) return 0;
        
        // Check for math overflow before we calculate
        if (amount > type(uint256).max / taxBps) revert TXN_OVERFLOW();
        
        return (amount * taxBps) / BASIS_POINTS;
    }
    
    /// @notice The fixed fee PancakeSwap takes (0.25%)
    uint256 private constant DEX_FEE_BPS = 25;
    
    /**
     * @dev Internal function to calculate price impact of a token sale using AMM mathematics.
     *      Uses the constant product formula (x + dx)(y - dy) = xy to determine how much
     *      the sale will move the price. Accounts for both sell tax and DEX fee (0.25%).
     *      Returns BASIS_POINTS (100%) if reserves are invalid or router not set.
     * @param amount The amount of tokens being sold (before tax)
     * @param pair The liquidity pair address to calculate impact against
     * @return impact The price impact in basis points where 100 = 1%, max 10000 = 100%
     * @custom:formula outputImpact = (idealOutput - actualOutput) / idealOutput * BASIS_POINTS
     * @custom:assumptions Factors in sellTaxBps and DEX_FEE_BPS (25 = 0.25%) before calculation
     * @custom:safety Returns 0 if router/pair not set, returns BASIS_POINTS if reserves are zero
     */
    function _calculatePriceImpact(uint256 amount, address pair) internal view returns (uint256 impact) {
        if (pancakeRouter == address(0) || pair == address(0) || amount == 0) return 0;

        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(pair).getReserves();
        
        uint256 reserveToken;
        uint256 reserveOther;
        if (IPancakePair(pair).token0() == address(this)) {
            reserveToken = reserve0;
            reserveOther = reserve1;
        } else {
            reserveToken = reserve1;
            reserveOther = reserve0;
        }

        if (reserveToken == 0 || reserveOther == 0) return BASIS_POINTS;

        // Factor in the sell tax first
        uint256 taxAmount = (amount * sellTaxBps) / BASIS_POINTS;
        uint256 amountAfterTax = amount - taxAmount;
        
        // Then factor in the DEX fee
        uint256 amountAfterFee = (amountAfterTax * (BASIS_POINTS - DEX_FEE_BPS)) / BASIS_POINTS;
        
        // Math magic to find the price movement
        uint256 outputWithoutImpact = (reserveOther * amountAfterFee) / reserveToken;
        uint256 outputWithImpact = (reserveOther * amountAfterFee) / (reserveToken + amountAfterFee);
        
        if (outputWithoutImpact == 0) return BASIS_POINTS;
        
        // Find the difference and turn it into a percentage
        uint256 impactAmount = outputWithoutImpact - outputWithImpact;
        impact = (impactAmount * BASIS_POINTS) / outputWithoutImpact;
        
        if (impact > BASIS_POINTS) impact = BASIS_POINTS;
        
        return impact;
    }


    
    /**
     * @dev Internal pure function to recover the signer address from an ECDSA signature.
     *      Implements Ethereum's ecrecover with additional security validations including
     *      signature malleability checks (s-value validation) to prevent signature replay attacks.
     *      Used for categorized transactions to verify off-chain authorization.
     * @param _ethSignedMessageHash The keccak256 hash of the signed message (prefixed with \x19Ethereum Signed Message:\n32)
     * @param _signature The raw 65-byte ECDSA signature containing r, s, and v components
     * @return signer The address that created the signature, or address(0) if validation fails
     * @custom:security Validates signature length (65 bytes), v value (27/28), and s-value malleability
     * @custom:format Signature format: bytes32(r) + bytes32(s) + uint8(v)
     */
    function _recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address) {
        if (_signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Assembly magic to pull r, s, and v out of the signature bytes
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);

        // Security check for the "s" value
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        address recovered = ecrecover(_ethSignedMessageHash, v, r, s);
        if (recovered == address(0)) return address(0);
        
        return recovered;
    }

    /**
     * @dev Internal function to initialize the PancakeSwap liquidity pair for NTE/WBNB.
     *      Performs a multi-step setup: queries factory from router, gets WETH address,
     *      checks for existing pair or creates new one, and registers it in isPancakePair.
     *      This is called during deployment to establish the primary trading pair.
     * @param _router A validated PancakeSwap router address (must be a contract)
     * @custom:effects Sets pancakePair state variable and registers it in isPancakePair mapping
     * @custom:security Multiple validation steps with specific error codes for each failure point
     * @custom:reverts DEX_FACTORY_ZERO, DEX_FACTORY, DEX_WETH_ZERO, DEX_WETH, DEX_PAIR_ZERO, etc.
     * @custom:note Caller must set pancakeRouter separately and emit appropriate events
     */
    function _initializeDexPair(address _router) internal {
        try IPancakeRouter(_router).factory() returns (address factory) {
            if (factory == address(0)) revert DEX_FACTORY_ZERO();
            if (!_isContract(factory)) revert DEX_FACTORY();

            try IPancakeRouter(_router).WETH() returns (address weth) {
                if (weth == address(0)) revert DEX_WETH_ZERO();
                if (!_isContract(weth)) revert DEX_WETH();

                try IPancakeFactory(factory).getPair(address(this), weth) returns (address existingPair) {
                    if (existingPair != address(0)) {
                        pancakePair = existingPair;
                    } else {
                        address newPair = IPancakeFactory(factory).createPair(address(this), weth);
                        if (newPair == address(0)) revert DEX_PAIR_ZERO();
                        pancakePair = newPair;
                    }
                    isPancakePair[pancakePair] = true;
                    if (pancakePair == address(0)) revert DEX_PAIR_FAIL();
                } catch {
                    revert DEX_PAIR_CHECK();
                }
            } catch {
                revert DEX_WETH_CALL();
            }
        } catch {
            revert DEX_FACTORY_CALL();
        }
    }

    /**
     * @dev Internal view function to determine if an address contains contract code.
     *      Uses the EXTCODESIZE opcode via inline assembly to check if bytecode exists
     *      at the address. Returns false for EOAs (externally owned accounts) and true
     *      for deployed contracts. Note: returns false during contract construction.
     * @param account The address to check for contract code
     * @return hasCode True if the address is a contract (has code), false otherwise
     * @custom:gas Low gas cost view function using inline codesize check
     * @custom:caveat Returns false for contracts in construction phase
     */
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /**
     * @dev Fallback function to receive BNB/native currency sent directly to the contract.
     *      This allows the contract to accept BNB from liquidity operations, tax conversions,
     *      or any other source. Logs all incoming transfers with sender and amount.
     * @custom:events Emits BNBReceived event with sender address and amount
     * @custom:usage Automatically called when BNB is sent without data to contract
     */
    receive() external payable {
        // Just log it so we know where it came from
        emit BNBReceived(msg.sender, msg.value);
    }
}
