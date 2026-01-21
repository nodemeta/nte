// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ SYSTEM & SECURITY [SYS_*, SEC_*]                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 * SYS_PAUSED       Contract is paused            SEC_REENTRY        No reentrancy allowed
 * SYS_DISABLED     Transfers are disabled        SEC_BOT_ACTIVE     Anti-bot period active
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ DEX & LIQUIDITY [DEX_*]                                                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 * DEX_ROUTER       Router isn't a contract       DEX_PAIR_ZERO      Pair address is zero
 * DEX_FACTORY_ZERO Factory address is zero       DEX_PAIR_FAIL      Failed to set up pair
 * DEX_FACTORY      Factory isn't a contract      DEX_PAIR_CHECK     Pair validation failed
 * DEX_WETH_ZERO    WETH address is zero          DEX_WETH_CALL      WETH call failed
 * DEX_WETH         WETH isn't a contract         DEX_FACTORY_CALL   Factory call failed
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
 * WL_REQUIRED      You need to be whitelisted
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ TRANSACTION CHECKS [TXN_*, ADDR_*]                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * TXN_AMOUNT_ZERO  Need to send more than 0      TXN_EXCEEDS_BAL    Not enough tokens
 * ADDR_FROM_ZERO   Sending from zero address     TXN_OVERFLOW       Math overflow detected
 * ADDR_TO_ZERO     Sending to zero address       TXN_SUPPLY_ZERO    Initial supply can't be 0
 * TXN_REPLAY       This transaction was used
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
 * TXN_REPLAY       This transaction was used     TXN_TAX_MISMATCH   Internal tax math mismatch
 * └─────────────────────────────────────────────────────────────────────────┘
 * CAT_INVALID      This category doesn't exist   CAT_DISABLED       Category is turned off
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ EMERGENCY RESCUE [EMG_*]                                                │
 * └─────────────────────────────────────────────────────────────────────────┘
 * EMG_TRANSFER_FAIL Token transfer failed         EMG_INVALID_RECIP  Recipient is invalid
 * EMG_INVALID_TOKEN Token address is invalid      EMG_INSUF_BAL_BNB  Not enough BNB
 * EMG_ZERO_RECIP   Recipient is zero address      EMG_BNB_FAIL       BNB transfer failed
 * EMG_INSUF_BAL    Not enough balance            EMG_WAIT_30D       Wait 30 days after launch
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ GENERAL CHECKS [ADDR_*]                                                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 * ADDR_INVALID     Address is invalid or zero    ADDR_ZERO          Zero address not allowed
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
    event transactionProcessed(address indexed from, address indexed to, uint256 value, uint8 category, string referenceId, string memo);
}

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
    
    /// @notice A master switch to stop all transfers if something goes wrong
    bool private _paused;
    
    /// @notice Wallets authorized to sign off-chain instructions (apps, websites, services)
    mapping(address => bool) public isAuthSigner;
    
    /// @notice The wallet where all collected taxes are sent
    address public treasury;
    
    /// @notice Tax taken when buying (in basis points: 100 = 1%)
    uint256 public buyTaxBps;
    /// @notice Tax taken when selling
    uint256 public sellTaxBps;
    /// @notice Tax taken for standard wallet-to-wallet transfers
    uint256 public transferTaxBps;
    
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
    bool public antiBotEnabled;
    /// @notice When the contract was first deployed
    uint256 public launchTime;
    /// @notice How long the anti-bot protection lasts after launch
    uint256 public antiBotDuration;
    
    // ===================================================
    // SMART CATEGORIES - Organized Payments
    // ===================================================
    
    /// @notice Details for a categorized transaction
    struct CategorizedTransaction {
        address from;
        address to;
        uint256 amount;
        uint8 category;
        string txReference;
        string memo;
        uint256 timestamp;
    }
    
    /// @notice How many trades happened in each category
    mapping(uint8 => uint256) public categoryTransactionCount;
    /// @notice Total volume of tokens moved per category
    mapping(uint8 => uint256) public categoryTotalVolume;
    /// @notice Your personal trade count per category
    mapping(address => mapping(uint8 => uint256)) public userCategoryCount;
    /// @notice Your personal volume per category
    mapping(address => mapping(uint8 => uint256)) public userCategoryVolume;
    
    /// @notice A list of the most recent categorized transfers
    CategorizedTransaction[] private recentCategorizedTxs;
    /// @notice We only keep the last 100 categorized trades in memory
    uint256 public constant MAX_STORED_TXS = 100;
    /// @notice Internal tracker for the rolling transaction list
    uint256 private _categorizedTxCounter;
    
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
    mapping(address => bool) public priceImpactExempt;
    
    /// @notice Whether we're forcing a wait time between every trade
    bool public walletCooldownEnabled;
    /// @notice The mandatory wait time between trades (in seconds)
    uint256 public globalCooldownSeconds;
    /// @notice When a wallet last made a trade
    mapping(address => uint256) public lastTradeTime;
    
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

    
    /// @notice The last time we updated the tax rates
    uint256 private _lastTaxChangeTime;
    /// @notice Safety rule: taxes can only be changed once every 24 hours
    uint256 private constant TAX_CHANGE_COOLDOWN = 1 days;
    
    /// @notice Whether even the owner is blocked when the contract is paused
    bool public pauseIncludesOwner;
    
    
    /// @notice Whether our "MEV Shield" is active against bots
    bool public mevProtectionEnabled;
    /// @notice How many blocks apart trades must be
    uint256 public maxBlocksForMevProtection;
    /// @notice Keeping track of which block a wallet last traded in
    mapping(address => uint256) public lastBlockNumber;
    /// @notice People who are allowed to bypass MEV checks
    mapping(address => bool) public mevProtectionExempt;
    /// @notice Minimum time (in seconds) between trades
    uint256 public minTimeBetweenTxs;
    
    // ===================================================
    // VELOCITY CONTROL - Slowing Down the Pace
    // ===================================================
    
    /// @notice Whether we're limiting how many trades you can do in a row
    bool public velocityLimitEnabled;
    /// @notice The "speed limit" for transactions
    uint256 public maxTxPerWindow;
    /// @notice The time window (in seconds) for the speed limit
    uint256 public velocityTimeWindow;
    
    /// @notice Max number of trades we track for the speed limit
    uint256 public constant MAX_VELOCITY_BUFFER = 10;
    /// @notice Internal counter for your "speed limit" tracker
    mapping(address => uint256) private userVelocityIndex;
    /// @notice A list of your most recent trade timestamps
    /// @dev We keep it at 10 to keep gas costs low.
    mapping(address => uint256[MAX_VELOCITY_BUFFER]) private userVelocityBuffer;

    /**
     * @notice People who don't have a "speed limit" on their trades.
     */
    mapping(address => bool) public velocityLimitExempt;

    // ===================================================
    // EVENTS
    // ===================================================
    
    /// @notice Emitted when contract ownership changes
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
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
    /// @notice Emitted when blacklist expiry is set or cleared
    event BlacklistExpirySet(address indexed account, uint256 expiryTime);
    /// @notice Emitted when whitelist expiry is set or cleared
    event WhitelistExpirySet(address indexed account, uint256 expiryTime);
    /// @notice Emitted when a DEX pair status is added or removed
    event DexPairUpdated(address indexed pair, bool isPair);
    /// @notice Emitted when emergency token withdrawal occurs
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);

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
    // CONSTRUCTOR
    // ===================================================
    
    error SEC_REENTRY();
    error AUTH_OWNER();
    error AUTH_ZERO_OWNER();
    error AUTH_LOCKED();
    error AUTH_SAME_OWNER();
    error AUTH_INVALID();
    error SYS_PAUSED();
    error SYS_DISABLED();
    error DEX_ROUTER();
    error DEX_FACTORY_ZERO();
    error DEX_FACTORY();
    error DEX_WETH_ZERO();
    error DEX_WETH();
    error DEX_PAIR_ZERO();
    error DEX_PAIR_FAIL();
    error DEX_PAIR_CHECK();
    error DEX_WETH_CALL();
    error DEX_FACTORY_CALL();
    error TAX_BUY_HIGH();
    error TAX_SELL_HIGH();
    error TAX_XFER_HIGH();
    error TAX_TOTAL_HIGH();
    error TAX_COOLDOWN();
    error TAX_BUY_DELTA();
    error TAX_SELL_DELTA();
    error TAX_XFER_DELTA();
    error TAX_TREASURY_ZERO();
    error TAX_TREASURY_SAME();
    error BL_OWNER();
    error BL_CONTRACT();
    error BL_SENDER();
    error BL_RECIPIENT();
    error WL_REQUIRED();
    error TXN_AMOUNT_ZERO();
    error TXN_EXCEEDS_BAL();
    error TXN_OVERFLOW();
    error TXN_SUPPLY_ZERO();
    error TXN_REPLAY();
    error TXN_TAX_MISMATCH();
    error ADDR_FROM_ZERO();
    error ADDR_TO_ZERO();
    error APRV_FROM_ZERO();
    error APRV_TO_ZERO();
    error APRV_OVERFLOW();
    error APRV_UNDERFLOW();
    error APRV_INSUFFICIENT();
    error MINT_TO_ZERO();
    error BURN_FROM_ZERO();
    error BURN_EXCEEDS();
    error MEV_VELOCITY();
    error MEV_TOO_FAST();
    error CD_SENDER();
    error CD_RECIPIENT();
    error CD_SELL();
    error DUMP_PERCENT();
    error DUMP_EXCEEDS();
    error PRICE_MIN_IMPACT();
    error PRICE_INVALID();
    error PRICE_TOO_HIGH();
    error CAT_INVALID();
    error CAT_DISABLED();
    error EMG_INVALID_TOKEN();
    error EMG_ZERO_RECIP();
    error EMG_INSUF_BAL();
    error EMG_TRANSFER_FAIL();
    error EMG_WAIT_30D();
    error EMG_INVALID_RECIP();
    error EMG_INSUF_BAL_BNB();
    error EMG_BNB_FAIL();
    error ADDR_INVALID();
    error ADDR_ZERO();
    error AUTH_ALREADY_SET();
    error AUTH_NOT_SET();
    error AUTH_ZERO_ADDR();
    error SEC_BOT_ACTIVE();
    error MEV_BLOCKS_HIGH();
    error MEV_TIME_HIGH();
    error CD_TOO_HIGH();

    /**
     * @dev Sets up the initial state of the NTE token.
     *      We initialize the supply, set the default taxes, and attempt to 
     *      integrate with PancakeSwap right away to save time later.
     * @param initialSupply How many tokens to start with (before decimals).
     * @param initialOwner The address that will hold the initial supply and admin keys.
     * @param _treasury Where the tax money goes (defaults to the owner if left empty).
     * @param _pancakeRouter The PancakeSwap router address for auto-pairing.
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
            
            try IPancakeRouter(_pancakeRouter).factory() returns (address factory) {
                if (factory == address(0)) revert DEX_FACTORY_ZERO();
                if (!_isContract(factory)) revert DEX_FACTORY();
                
                try IPancakeRouter(_pancakeRouter).WETH() returns (address weth) {
                    if (weth == address(0)) revert DEX_WETH_ZERO();
                    if (!_isContract(weth)) revert DEX_WETH();
                    
                    try IPancakeFactory(factory).getPair(address(this), weth) returns (address existingPair) {
                        if (existingPair != address(0)) {
                            pancakePair = existingPair;
                            isPancakePair[pancakePair] = true;
                        } else {
                            address newPair = IPancakeFactory(factory).createPair(address(this), weth);
                            if (newPair == address(0)) revert DEX_PAIR_ZERO();
                            pancakePair = newPair;
                            isPancakePair[pancakePair] = true;
                        }
                        
                        if (pancakePair == address(0)) revert DEX_PAIR_FAIL();
                        pancakeRouter = _pancakeRouter;
                        // Router is NOT tax exempt to prevent arbitrage through direct router calls
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
        
        antiDumpEnabled = false;
        maxSellPercentage = 100;
        sellCooldown = 0;
        
        whitelistEnabled = false;
        
        totalCategories = 0;
        
        priceImpactLimitEnabled = false;
        maxPriceImpactPercent = 500;
        
        walletCooldownEnabled = false;
        globalCooldownSeconds = 30;
        
        mevProtectionEnabled = true;
        maxBlocksForMevProtection = 2;
        minTimeBetweenTxs = 12;
        
        antiBotEnabled = true;
        antiBotDuration = 3900;
        launchTime = block.timestamp;
        
        velocityLimitEnabled = false;
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
     * @notice Returns the token name.
     */
    function name() public view returns (string memory) {
        return _name;
    }
    
    /**
     * @notice Returns the token symbol (ticker).
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    /**
     * @notice Returns how many decimal places the token uses.
     */
    function decimals() public pure returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Returns the total amount of tokens currently in circulation.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @notice Checks how many tokens a specific wallet is holding.
     * @param account The address to check.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @notice Moves tokens from your wallet to someone else's.
     * @param to The lucky recipient.
     * @param amount How many tokens to send.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithTax(msg.sender, to, amount);
        return true;
    }
    
    /**
     * @notice Checks how many tokens a spender is allowed to use on your behalf.
     */
    function allowance(address account, address spender) public view override returns (uint256) {
        return _allowances[account][spender];
    }
    
    /**
     * @notice Giving someone permission to spend your tokens.
     * @param spender The person or contract you're authorizing.
     * @param amount The limit of how many tokens they can spend.
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @notice Moving tokens from one person to another using a pre-approved allowance.
     * @param from Where the tokens are coming from.
     * @param to Where the tokens are going.
     * @param amount How many tokens to move.
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
     * @notice Send tokens with a specific "Category" and a personal memo.
    * @dev This is a special transfer that requires a digital signature from an
    *      authorized off-chain signer (for example, a backend for your app or website).
    *      It's great for business payments or tagging rewards.
     *      We use a nonce, chainId, and the contract address to make sure nobody 
     *      can "replay" or steal your transaction data.
     * @param to Who is receiving the tokens.
     * @param amount How many tokens to send.
     * @param category The ID of the category (e.g., 1 for 'Business').
    * @param signature The secure signature from an authorized backend signer.
     * @param nonce Your current transaction count (to prevent double-spending).
     * @param txReference An invoice or order number for your records.
     * @param memo A short note about the transfer.
     * @return True if everything went smoothly.
     */
    /**
     * @notice Category-based transfer where the actual payer is an explicit `from` address.
     * @dev This version allows a relayer or helper contract to call the function while
     *      the tokens are pulled from `from` using the standard ERC20 allowance flow.
     *      Flow:
     *        - Off-chain backend signs over (this, from, to, amount, category, txRef, nonce, chainId).
     *        - `from` grants allowance to the caller (e.g. helper) once.
     *        - Caller invokes TransactionFrom(from, to, ...) and pays gas.
     *      Security:
     *        - Nonce is tracked per `from` address (userCategorizedNonce[from]).
     *        - Signature still bound to contract and deployment chain id.
     */
    function TransactionFrom(
        address from,
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        if (from == address(0)) revert ADDR_FROM_ZERO();

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

        if (bytes(txReference).length > MAX_STRING_LENGTH) revert ADDR_INVALID();
        if (bytes(memo).length > MAX_STRING_LENGTH) revert ADDR_INVALID();

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

        CategorizedTransaction memory newTx = CategorizedTransaction({
            from: from,
            to: to,
            amount: amount,
            category: category,
            txReference: txReference,
            memo: memo,
            timestamp: block.timestamp
        });

        uint256 currentIndex = _categorizedTxCounter % MAX_STORED_TXS;
        if (recentCategorizedTxs.length < MAX_STORED_TXS) {
            recentCategorizedTxs.push(newTx);
        } else {
            recentCategorizedTxs[currentIndex] = newTx;
        }
        _categorizedTxCounter++;

        userCategorizedNonce[from] = expectedNonce + 1;

        emit transactionProcessed(from, to, amount, category, txReference, memo);
        emit CategoryStatsUpdated(category, categoryTransactionCount[category], categoryTotalVolume[category]);

        return true;
    }
    
    /**
     * @notice Returns the display name of a payment category.
     * @param category The ID of the category to query.
     * @return The string name of the category.
     */
    function getCategoryName(uint8 category) external view returns (string memory) {
        if (category >= totalCategories) revert CAT_INVALID();
        return categoryNames[category];
    }
    
    /**
     * @notice Enables or disables a specific payment category.
     * @param category The ID of the category to update.
     * @param enabled True to enable, false to disable.
     */
    function setCategoryEnabled(uint8 category, bool enabled) external onlyOwner {
        if (category >= totalCategories) revert CAT_INVALID();
        categoryEnabled[category] = enabled;
        emit CategoryStatusUpdated(category, enabled);
    }
    
    /**
     * @notice Updates the display name of an existing category.
     * @param category The ID of the category to update.
     * @param newName The new name for the category.
     */
    function updateCategoryName(uint8 category, string calldata newName) external onlyOwner {
        if (category >= totalCategories) revert CAT_INVALID();
        if (bytes(newName).length == 0) revert ADDR_INVALID();
        if (bytes(newName).length > MAX_STRING_LENGTH) revert ADDR_INVALID();
        categoryNames[category] = newName;
        emit CategoryUpdated(category, newName);
    }
    
    /**
     * @notice Adds a new payment category to the system.
     * @param categoryName The name of the new category.
     * @return categoryId The ID assigned to the new category.
     */
    function addCategory(string calldata categoryName) external onlyOwner returns (uint8 categoryId) {
        if (bytes(categoryName).length == 0) revert ADDR_INVALID();
        if (bytes(categoryName).length > MAX_STRING_LENGTH) revert ADDR_INVALID();
        if (totalCategories == 255) revert CAT_INVALID();
        
        categoryId = totalCategories;
        categoryNames[categoryId] = categoryName;
        categoryEnabled[categoryId] = true;
        totalCategories++;
        
        emit CategoryAdded(categoryId, categoryName);
        return categoryId;
    }

    /**
     * @notice Authorizes a new off-chain signer for categorized transfers.
     * @dev Signer addresses should be managed securely (e.g., using a HSM, KMS, or backend service).
     * @param authAddress The address of the off-chain signer (website, app, or service backend).
     */
    function addAuthSigner(address authAddress) external onlyOwner {
        if (authAddress == address(0)) revert ADDR_ZERO();
        if (isAuthSigner[authAddress]) revert AUTH_ALREADY_SET();
        isAuthSigner[authAddress] = true;
        emit AuthSignerAdded(authAddress);
    }

    /**
     * @notice Revokes authorization from an off-chain signer.
     * @param authAddress The address to remove from the authorized list.
     */
    function removeAuthSigner(address authAddress) external onlyOwner {
        if (!isAuthSigner[authAddress]) revert AUTH_NOT_SET();
        isAuthSigner[authAddress] = false;
        emit AuthSignerRemoved(authAddress);
    }

    /**
     * @notice Burns tokens from the caller's balance, reducing the total supply.
     * @param amount The number of tokens to be destroyed.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    /**
     * @notice Checks if the contract is currently in a paused state.
     * @return True if the contract is paused, otherwise false.
     */
    function paused() public view returns (bool) {
        return _paused;
    }
    
    /**
     * @notice Returns the address of the current contract owner.
     * @return The address of the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }
    
    /**
     * @notice Returns the URL pointing to the token's official logo.
     * @return The logo metadata URL string.
     */
    function tokenURI() public pure returns (string memory) {
        return _tokenLogo;
    }
    
    /**
     * @notice Returns the nonce for categorized transfers for an account.
     * @param account The address to check.
     * @return The current nonce.
     */
    function getCategorizedNonce(address account) public view returns (uint256) {
        return userCategorizedNonce[account];
    }
    
    /**
     * @notice Returns a comprehensive summary of token metadata.
     * @return tokenName The full name of the token.
     * @return tokenSymbol The ticker symbol of the token.
     * @return tokenDecimals The number of decimal places used.
     * @return tokenTotalSupply The current total circulating supply.
     * @return logo The token's logo URI.
     * @return description A brief project description.
     * @return website The official project website URL.
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
     * @notice Returns the current tax configuration settings.
     * @return buyTax The tax rate applied to buy transactions (in basis points).
     * @return sellTax The tax rate applied to sell transactions (in basis points).
     * @return transferTax The tax rate applied to wallet-to-wallet transfers (in basis points).
     * @return treasuryAddr The address where collected taxes are sent.
     * @return routerExempt Indicates if the main DEX router is exempt from taxes.
     * @return pairExempt Indicates if the main DEX pair is exempt from taxes.
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
     * @notice Owner: pauses all token transfers and trading.
     * @param includeOwner If true, owner is also blocked while paused.
     */
    function pause(bool includeOwner) external onlyOwner {
        _paused = true;
        pauseIncludesOwner = includeOwner;
        emit Paused(msg.sender);
    }
    
    /**
     * @notice Owner: unpauses the contract and resumes trading.
     */
    function unpause() external onlyOwner {
        _paused = false;
        pauseIncludesOwner = false;
        emit Unpaused(msg.sender);
    }
    
    /**
     * @notice Renounces contract ownership, making the contract ownerless.
     * @dev Only possible 30 days after launch for security.
     */
    function renounceOwnership() public onlyOwner {
        if (block.timestamp <= launchTime + 30 days) revert AUTH_LOCKED();
        address previousOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }
    
    /**
     * @notice Transfers contract ownership to a new address.
     * @param newOwner The address of the new owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert AUTH_ZERO_OWNER();
        if (newOwner == _owner) revert AUTH_SAME_OWNER();
        address previousOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
    
    /// @notice Maximum allowed sell tax (safety limit)
    uint256 public constant MAX_SELL_TAX_LIMIT = 2500;
    
    /**
     * @notice Get a quick estimate of what happens when you sell.
     * @dev This is great for transparency. It calculates the taxes and 
     *      the expected "Price Impact" so you aren't surprised by the result.
     * @param amount The number of tokens you're thinking of selling.
     * @return netOutput What you'll actually receive after taxes.
     * @return taxAmount How many tokens go to the treasury.
     * @return impactBps The price impact (100 = 1% move in price).
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
        impactBps = _calculatePriceImpact(amount);
        
        return (netOutput, taxAmount, impactBps);
    }

    /**
     * @notice Updates the tax rates for buy, sell, and transfer transactions.
     * @dev Rates are in basis points (100 = 1%). Subject to safety limits and cooldown.
     * @param newBuyTaxBps New buy tax rate.
     * @param newSellTaxBps New sell tax rate.
     * @param newTransferTaxBps New transfer tax rate.
     */
    function setAllTaxBasisPoints(
        uint256 newBuyTaxBps,
        uint256 newSellTaxBps,
        uint256 newTransferTaxBps
    ) external onlyOwner {
        if (newBuyTaxBps > 2500) revert TAX_BUY_HIGH();
        if (newSellTaxBps > MAX_SELL_TAX_LIMIT) revert TAX_SELL_HIGH();
        if (newTransferTaxBps > 2500) revert TAX_XFER_HIGH();
        if (newBuyTaxBps + newSellTaxBps + newTransferTaxBps > 5000) revert TAX_TOTAL_HIGH();
        if (block.timestamp < _lastTaxChangeTime + TAX_CHANGE_COOLDOWN) revert TAX_COOLDOWN();
        
        uint256 buyChange = newBuyTaxBps > buyTaxBps ? newBuyTaxBps - buyTaxBps : buyTaxBps - newBuyTaxBps;
        uint256 sellChange = newSellTaxBps > sellTaxBps ? newSellTaxBps - sellTaxBps : sellTaxBps - newSellTaxBps;
        uint256 transferChange = newTransferTaxBps > transferTaxBps ? newTransferTaxBps - transferTaxBps : transferTaxBps - newTransferTaxBps;
        
        if (buyChange > 250) revert TAX_BUY_DELTA();
        if (sellChange > 250) revert TAX_SELL_DELTA();
        if (transferChange > 250) revert TAX_XFER_DELTA();
        
        buyTaxBps = newBuyTaxBps;
        sellTaxBps = newSellTaxBps;
        transferTaxBps = newTransferTaxBps;
        _lastTaxChangeTime = block.timestamp;
        
        emit TaxRatesUpdated(newBuyTaxBps, newSellTaxBps, newTransferTaxBps);
    }
    
    /**
     * @notice Configures auto-liquidity routing for collected taxes.
     * @dev When enabled, a percentage of each tax amount is sent to a
     *      dedicated liquidity manager contract, with the remainder still
     *      going to the treasury.
     * @param enabled True to enable routing part of tax to the liquidity manager.
     * @param percentageBps Portion of the tax to send, in basis points (100 = 1%).
     * @param collector Address of the liquidity manager contract.
     */
    function configureAutoLiquidity(
        bool enabled,
        uint256 percentageBps,
        address collector
    ) external onlyOwner {
        if (percentageBps > BASIS_POINTS) revert PRICE_INVALID();
        if (enabled && collector == address(0)) revert ADDR_ZERO();
        autoLiquidityEnabled = enabled;
        autoLiquidityBps = percentageBps;
        liquidityCollector = collector;
        emit AutoLiquidityConfigUpdated(enabled, percentageBps, collector);
    }
    
    /**
     * @notice Sets the tax exemption status for a specific address.
     * @param user The address to update.
     * @param exempt True to exempt, false to apply taxes.
     */
    function setTaxExempt(address user, bool exempt) external onlyOwner {
        if (user == address(0)) revert ADDR_INVALID();
        taxExempt[user] = exempt;
        emit TaxExemptUpdated(user, exempt);
    }
    
    /**
     * @notice Manages the blacklist status for a specific address.
     * @param account The address to blacklist or unblacklist.
     * @param blacklisted True to blacklist, false to unblacklist.
     * @param expiryTime Timestamp when the blacklist expires (0 for permanent).
     */
    function setBlacklist(address account, bool blacklisted, uint256 expiryTime) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        if (account == _owner) revert BL_OWNER();
        if (account == address(this)) revert BL_CONTRACT();
        isBlacklisted[account] = blacklisted;
        if (blacklisted && expiryTime > 0) {
            if (expiryTime <= block.timestamp) revert ADDR_INVALID();
            blacklistExpiry[account] = expiryTime;
            emit BlacklistExpirySet(account, expiryTime);
        } else {
            blacklistExpiry[account] = 0;
        }
        emit BlacklistUpdated(account, blacklisted);
    }

    /**
     * @notice Toggles the whitelist-only trading mode.
     * @param enabled True to enable whitelist-only mode.
     */
    function setWhitelistMode(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistModeUpdated(enabled);
    }

    /**
     * @notice Manages the whitelist status for a specific address.
     * @param account The address to whitelist or unwhitelist.
     * @param whitelisted True to whitelist, false to unwhitelist.
     * @param expiryTime Timestamp when the whitelist expires (0 for permanent).
     */
    function setWhitelist(address account, bool whitelisted, uint256 expiryTime) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        isWhitelisted[account] = whitelisted;
        if (whitelisted && expiryTime > 0) {
            if (expiryTime <= block.timestamp) revert ADDR_INVALID();
            whitelistExpiry[account] = expiryTime;
            emit WhitelistExpirySet(account, expiryTime);
        } else {
            whitelistExpiry[account] = 0;
        }
        emit WhitelistUpdated(account, whitelisted);
    }

    /**
     * @notice Updates the treasury address.
     * @param newTreasury The proposed new treasury address.
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert TAX_TREASURY_ZERO();
        if (newTreasury == treasury) revert TAX_TREASURY_SAME();
        
        treasury = newTreasury;
        
        emit TreasuryUpdated(newTreasury);
    }

    /**
     * @notice Configures anti-dump protection settings.
     * @param enabled True to enable anti-dump logic.
     * @param maxPercentage Max percentage of total supply allowed per sell.
     * @param cooldownTime Cooldown period between large sells.
     */
    function setAntiDumpConfig(bool enabled, uint256 maxPercentage, uint256 cooldownTime) external onlyOwner {
        if (maxPercentage == 0 || maxPercentage > 100) revert DUMP_PERCENT();
        if (cooldownTime > MAX_ANTI_DUMP_COOLDOWN) revert CD_TOO_HIGH();
        antiDumpEnabled = enabled;
        maxSellPercentage = maxPercentage;
        sellCooldown = cooldownTime;
        emit AntiDumpConfigUpdated(enabled, maxPercentage, cooldownTime);
    }
    
    /**
     * @notice Configures price impact limit settings for DEX sells.
     * @param enabled True to enable price impact limits.
     * @param maxImpactBasisPoints Maximum allowed price impact in basis points.
     */
    function setPriceImpactLimitConfig(bool enabled, uint256 maxImpactBasisPoints) external onlyOwner {
        if (enabled && maxImpactBasisPoints < 10) revert PRICE_MIN_IMPACT();
        if (maxImpactBasisPoints > 10000) revert PRICE_INVALID();
        priceImpactLimitEnabled = enabled;
        maxPriceImpactPercent = maxImpactBasisPoints;
        emit PriceImpactLimitConfigUpdated(enabled, maxImpactBasisPoints);
    }
    
    /**
     * @notice Sets the price impact exemption status for a specific address.
     * @param account The address to update.
     * @param exempt True to exempt, false to apply limits.
     */
    function setPriceImpactExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        priceImpactExempt[account] = exempt;
        emit PriceImpactExemptUpdated(account, exempt);
    }
    
    /**
     * @notice Configures the global wallet cooldown settings.
     * @param enabled True to enable wallet cooldowns.
     * @param cooldownSeconds Number of seconds required between transactions.
     */
    function setWalletCooldownConfig(bool enabled, uint256 cooldownSeconds) external onlyOwner {
        if (cooldownSeconds > MAX_COOLDOWN) revert CD_TOO_HIGH();
        walletCooldownEnabled = enabled;
        globalCooldownSeconds = cooldownSeconds;
        emit WalletCooldownConfigUpdated(enabled, cooldownSeconds);
    }
    
    /**
     * @notice Emergency function to withdraw stuck ERC20 tokens from the contract.
    * @dev Can withdraw any ERC20 token held by this contract, including NTE.
    * @param token The address of the token to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
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
     * @notice Emergency function to withdraw BNB from the contract.
     * @dev Only possible 30 days after launch for security.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (block.timestamp <= launchTime + 30 days) revert EMG_WAIT_30D();
        if (to == address(0)) revert EMG_INVALID_RECIP();
        if (amount > address(this).balance) revert EMG_INSUF_BAL_BNB();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert EMG_BNB_FAIL();
    }

    /**
     * @notice Configures protection settings.
     * @param enabled True to enable transaction protection.
     * @param maxBlocks Maximum blocks allowed between transactions.
     * @param minTime Minimum time in seconds allowed between transactions.
     */
    function setMevProtectionConfig(bool enabled, uint256 maxBlocks, uint256 minTime) external onlyOwner {
        // When enabling protection, at least one of the parameters must be non-zero
        if (enabled && maxBlocks == 0 && minTime == 0) revert MEV_TIME_HIGH();
        if (maxBlocks > 10) revert MEV_BLOCKS_HIGH();
        if (minTime > 300) revert MEV_TIME_HIGH();

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
     * @notice Sets the protection exemption status for a specific address.
     * @param account The address to update.
     * @param exempt True to exempt, false to apply protection.
     */
    function setMevProtectionExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        mevProtectionExempt[account] = exempt;
        emit MevProtectionExemptUpdated(account, exempt);
    }
    
    /**
     * @notice Configures the transaction velocity protection settings.
     * @param enabled True to enable velocity protection.
     * @param maxTx Maximum allowed transactions per time window.
     * @param timeWindow The duration of the time window in seconds.
     */
    function setVelocityLimitConfig(bool enabled, uint256 maxTx, uint256 timeWindow) external onlyOwner {
        if (enabled) {
            if (maxTx == 0 || timeWindow == 0) revert ADDR_INVALID();
            if (maxTx > MAX_VELOCITY_BUFFER) revert CD_TOO_HIGH();
            if (timeWindow > 86400) revert CD_TOO_HIGH();
        }
        velocityLimitEnabled = enabled;
        maxTxPerWindow = maxTx;
        velocityTimeWindow = timeWindow;
        emit VelocityLimitConfigured(enabled, maxTx, timeWindow);
    }
    
    /**
     * @notice Sets the velocity protection exemption status for a specific address.
     * @param account The address to update.
     * @param exempt True to exempt, false to apply protection.
     */
    function setVelocityLimitExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert ADDR_INVALID();
        velocityLimitExempt[account] = exempt;
        emit VelocityLimitExemptUpdated(account, exempt);
    }

    /**
     * @notice Returns a summary of MEV and velocity protection configuration.
     * @return mevEnabled Whether MEV protection is enabled.
     * @return maxBlocks Maximum allowed blocks between trades for MEV checks.
     * @return minTime Minimum allowed time between trades for MEV checks.
     * @return velocityEnabled Whether velocity protection is enabled.
     * @return maxTx Maximum number of transactions allowed in the time window.
     * @return timeWindow The duration of the velocity protection window in seconds.
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
     * @notice Checks if an address is currently blacklisted and the restriction is active.
     * @param account The address to check.
     * @return True if the address is blacklisted and the restriction has not expired.
     */
    function isBlacklistedActive(address account) public view returns (bool) {
        if (!isBlacklisted[account]) return false;
        if (blacklistExpiry[account] == 0) return true; // Permanent restriction
        return block.timestamp < blacklistExpiry[account];
    }
    
    /**
     * @notice Cleans up expired blacklist entry for an account (callable by anyone).
     * @param account The address to clean up.
     */
    function cleanExpiredBlacklist(address account) external {
        if (isBlacklisted[account] && blacklistExpiry[account] != 0 && block.timestamp >= blacklistExpiry[account]) {
            isBlacklisted[account] = false;
            blacklistExpiry[account] = 0;
            emit BlacklistUpdated(account, false);
        }
    }
    
    /**
     * @notice Checks if an address is currently whitelisted and the permission is active.
     * @param account The address to check.
     * @return True if the address is whitelisted and the permission has not expired.
     */
    function isWhitelistedActive(address account) public view returns (bool) {
        if (!isWhitelisted[account]) return false;
        if (whitelistExpiry[account] == 0) return true; // Permanent permission
        return block.timestamp < whitelistExpiry[account];
    }
    
    /**
     * @notice Cleans up expired whitelist entry for an account (callable by anyone).
     * @param account The address to clean up.
     */
    function cleanExpiredWhitelist(address account) external {
        if (isWhitelisted[account] && whitelistExpiry[account] != 0 && block.timestamp >= whitelistExpiry[account]) {
            isWhitelisted[account] = false;
            whitelistExpiry[account] = 0;
            emit WhitelistUpdated(account, false);
        }
    }

    /**
     * @notice Registers or unregisters a DEX pair address for tax purposes.
     * @dev Use this to add new liquidity pairs on other DEXes to prevent tax evasion.
     * @param pair The address of the DEX pair contract.
     * @param status True to register as a DEX pair, false to unregister.
     */
    function setDexPairStatus(address pair, bool status) external onlyOwner {
        if (pair == address(0)) revert ADDR_INVALID();
        if (!_isContract(pair)) revert DEX_ROUTER(); // Reuse error - pair must be a contract
        // Prevent accidentally disabling the main pancakePair
        if (pair == pancakePair && !status) revert DEX_PAIR_CHECK();
        isPancakePair[pair] = status;
        emit DexPairUpdated(pair, status);
    }

    // ============================================
    // INTERNAL STUFF - For Our Eyes Only
    // ============================================
    
    /**
     * @dev Simple internal function to create new tokens.
     * @param account Who gets the new tokens.
     * @param amount How many to create (remember the 18 decimals!).
     */
    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert MINT_TO_ZERO();
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    
    /**
     * @dev Destroys tokens permanently.
     * @param account Where the tokens are coming from.
     * @param amount How many to burn.
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
     * @dev The actual move-money logic. No taxes or rules here, just pure math.
     * @param from Sender address.
     * @param to Recipient address.
     * @param amount Token amount.
     */
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ADDR_FROM_ZERO();
        if (to == address(0)) revert ADDR_TO_ZERO();
        
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert TXN_EXCEEDS_BAL();
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @dev Helping with the Approval event and setting the allowance.
     * @param tokenOwner Who owns the tokens.
     * @param spender Who can spend them.
     * @param amount The maximum they can use.
     */
    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        if (tokenOwner == address(0)) revert APRV_FROM_ZERO();
        if (spender == address(0)) revert APRV_TO_ZERO();
        _allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }

    /**
     * @notice Bump up the allowance you gave to someone.
     * @dev Much safer than calling `approve` again.
     * @param spender The person you're trusting.
     * @param addedValue How many extra tokens they can spend.
     * @return True if it worked.
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance + addedValue < currentAllowance) revert APRV_OVERFLOW();
        _approve(msg.sender, spender, currentAllowance + addedValue);
        return true;
    }
    
    /**
     * @dev Speed limit check for a wallet. We use a "circular buffer" 
     *      to keep the gas costs small and consistent.
     * @param account The address we're checking.
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
     * @notice Lower the allowance you gave to someone.
     * @param spender The person you're trusting less.
     * @param subtractedValue How many tokens to take away from their allowance.
     * @return True if it worked.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance < subtractedValue) revert APRV_UNDERFLOW();
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }
    
    /**
     * @dev Deduct from the allowance during a `transferFrom`.
     *      If someone has "infinite" allowance (max uint256), we don't bother deducting.
     * @param account Owner of the tokens.
     * @param spender Person spending them.
     * @param amount Tokens being spent.
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
    
    /// @notice Record that a trade happened so we can enforce cooldowns.
    function _updateTradingState(address account) internal {
        lastBlockNumber[account] = block.number;
        lastTradeTime[account] = block.timestamp;
    }

    /**
     * @dev This is the main engine room of the NTE token. It handles taxes, 
     *      security, and all the "anti-cheat" protections in one place.
     *      We check things in this order for safety:
     *      1. Is the whole contract paused?
     *      2. Are we still in the "Anti-Bot" launch minutes?
     *      3. Is the sender or receiver blacklisted?
     *      4. Is the wallet trading too fast (Velocity/MEV)?
     *      5. Finally, calculate taxes and move the tokens.
     * @param from The person sending.
     * @param to The person (or DEX pool) receiving.
     * @param amount The total tokens being moved.
     */
    function _transferWithTax(address from, address to, uint256 amount) internal nonReentrant {
        // Basic checks first
        if (amount == 0) revert TXN_AMOUNT_ZERO();
        if (from == address(0)) revert ADDR_FROM_ZERO();
        if (to == address(0)) revert ADDR_TO_ZERO();
        
        // If we're paused, everything stops (unless you're the owner)
        if (_paused) {
            if (pauseIncludesOwner) {
                revert SYS_DISABLED();
            } else {
                if (from != _owner && to != _owner) revert SYS_DISABLED();
            }
        }
        
        // Launch day shields - very strict for the first hour or so
        if (antiBotEnabled && block.timestamp < launchTime + antiBotDuration) {
            if (!(from == _owner || to == _owner || taxExempt[from] || taxExempt[to])) {
                revert SEC_BOT_ACTIVE();
            }
        }
        
        if (isBlacklistedActive(from)) revert BL_SENDER();
        if (isBlacklistedActive(to)) revert BL_RECIPIENT();
        
        if (whitelistEnabled) {
            if (!(from == _owner || to == _owner || 
                isWhitelistedActive(from) || isWhitelistedActive(to) ||
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
                emit MevAttackPrevented(from, block.number, "CONTRACT_SELL");
                revert MEV_VELOCITY();
            }
            
            // If it's a sell, we check if the wallet is brand new
            if (isSellToPair) {
                if (lastBlockNumber[from] == 0) {
                    emit MevAttackPrevented(from, block.number, "FRESH_WALLET_SELL");
                    revert MEV_VELOCITY();
                }
                // Even if not brand new, you can't sell if you just bought 60 seconds ago
                if (lastTradeTime[from] != 0 && block.timestamp - lastTradeTime[from] < 60) {
                    emit MevAttackPrevented(from, block.number, "NEW_WALLET_RAPID_SELL");
                    revert MEV_VELOCITY();
                }
            }
            
            // General speed checks for everyone else
            if (lastBlockNumber[from] != 0) {
                if (block.number > lastBlockNumber[from]) {
                    if ((block.number - lastBlockNumber[from]) <= maxBlocksForMevProtection) {
                        emit MevAttackPrevented(from, block.number, "MEV_BLOCK");
                        revert MEV_VELOCITY();
                    }
                }
                
                if ((block.timestamp - lastTradeTime[from]) < minTimeBetweenTxs) {
                    emit MevAttackPrevented(from, block.number, "MEV_TIME");
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
            uint256 priceImpact = _calculatePriceImpact(amount);
            if (priceImpact > maxPriceImpactPercent) revert PRICE_TOO_HIGH();
        }
        
        // Anti-dump - preventing massive sells that crash the price
        if (antiDumpEnabled && isToPair && !taxExempt[from]) {
            uint256 maxSellAmount = (_totalSupply * maxSellPercentage) / 100;
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
     * @dev Deciding which tax rate applies to this specific trade.
     *      We check if it's a Buy, a Sell, or just a friend-to-friend (P2P) move.
     * @param from Sender address.
     * @param to Recipient address.
     * @param amount Base amount.
     * @return The amount of tokens to take as tax.
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
        } else {
            // Just a regular P2P transfer
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
     * @dev Predicting how much the price will move if you sell this amount.
     *      We use the standard AMM formula: (x + dx)(y - dy) = xy
     * @param amount Tokens being sold.
     * @return impact Price impact in basis points (100 = 1%).
     */
    function _calculatePriceImpact(uint256 amount) internal view returns (uint256 impact) {
        if (pancakeRouter == address(0) || pancakePair == address(0) || amount == 0) return 0;

        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(pancakePair).getReserves();
        
        uint256 reserveToken;
        uint256 reserveOther;
        if (IPancakePair(pancakePair).token0() == address(this)) {
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
     * @dev Crypto helper to find out who signed a message.
     * @param _ethSignedMessageHash The message that was signed.
     * @param _signature The raw 65-byte signature.
     * @return The address that signed it (or zero address if invalid).
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
     * @dev Checking if an address is a contract or just a regular person's wallet.
     * @param account The address to check.
     * @return True if it's a contract.
     */
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /**
     * @dev Standard function to let the contract receive BNB directly.
     */
    receive() external payable {
        // Just log it so we know where it came from
        emit BNBReceived(msg.sender, msg.value);
    }
}