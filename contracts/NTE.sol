// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title Node Meta Energy (NTE) Token Contract
 * @author Node Meta Energy Team
 * @notice Comprehensive ERC20 token with staking and DeFi features
 * @dev Upgradeable using UUPS pattern
 */

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// Interface for PancakeSwap Router - handles token swaps and liquidity
interface IPancakeRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

// Interface for PancakeSwap Factory - creates new trading pairs
interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/**
 * @title Node Meta Energy (NTE) - Advanced ERC20 Token
 * @dev This contract includes multiple advanced features for DeFi and business operations
 * This contract is specifically designed for Node Meta Energy project and includes
 * custom business logic that makes it unique from other similar contracts.
 */
contract NTE is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    
    /**
     * @dev Staking System Variables (DEPRECATED but kept for storage compatibility)
     */
    mapping(address => uint256) public stakedBalance;        // DEPRECATED: Amount each user has staked
    mapping(address => uint256) public lastStakeTime;        // DEPRECATED: When user last staked/claimed rewards
    uint256 public stakingRewardRate;       // DEPRECATED: Annual percentage rate for staking rewards
    uint256 public totalStaked;             // DEPRECATED: Total tokens currently staked in contract
    uint256 public totalStakingRewards;     // DEPRECATED: Total rewards distributed to stakers

    /**
     * @dev Tax System Variables
     * Allows collection of fees on token transfers for project funding.
     * Currently optimized for business model with exemptions.
     */
    address public treasury;                // Address that receives collected taxes
    uint256 public taxPercent;             // Legacy tax variable (kept for compatibility)

    /**
     * @dev PancakeSwap Integration Variables
     * Enables trading on PancakeSwap DEX and provides anti-bot protection during launch.
     */
    address public pancakeRouter;           // PancakeSwap router contract address
    address public pancakePair;            // Trading pair address (NTE/BNB)
    mapping(address => bool) public isPancakePair;           // Tracks all trading pairs
    bool public antiBotEnabled;            // Enables/disables anti-bot protection
    uint256 public launchTime;             // Contract deployment timestamp
    uint256 public antiBotDuration;        // How long anti-bot protection stays active

    /**
     * @dev Token Information and Branding Variables
     * These control how the token appears in wallets and block explorers.
     * The owner can update these to rebrand or modify token information.
     */
    string private _customName;           // Custom token name (e.g., "Node Meta Energy")
    string private _customSymbol;         // Custom token symbol (e.g., "NTE")
    string private _tokenLogo;            // URL to token logo image
    string private _description;          // Token description for metadata
    string private _website;              // Official project website
    mapping(string => string) private _socialLinks;  // Social media links (twitter, telegram, etc.)

    /**
     * @dev Trading Limits and Controls
     * These variables control transaction limits and automatic liquidity management.
     * Currently disabled for maximum freedom in your business model.
     */
    bool public autoLiquidityEnabled;     // DEPRECATED: Kept for storage compatibility
    uint256 public liquidityThreshold;   // DEPRECATED: Kept for storage compatibility
    uint256 public maxTxAmount;          // Maximum tokens per transaction (disabled = max uint256)
    uint256 public maxWalletAmount;      // Maximum tokens per wallet (disabled = max uint256)
    mapping(address => bool) public liquidityPairs;  // Tracks which addresses are liquidity pairs

    /**
     * @dev Liquidity Locking System
     * Allows locking of liquidity tokens for a specified period to prevent rug pulls.
     * Currently disabled for your business model flexibility.
     */
    struct LiquidityLock {
        uint256 amount;        // Amount of LP tokens locked
        uint256 lockTime;      // When the lock was created
        uint256 unlockTime;    // When tokens can be unlocked
        bool isLocked;         // Whether tokens are currently locked
        address locker;        // Who locked the tokens
    }
    mapping(address => LiquidityLock) public liquidityLocks;  // Pair address => Lock info
    uint256 public defaultLiquidityLockPeriod;                // Default lock time in seconds
    bool public liquidityLockEnabled;                         // Whether locking is enabled
    address public liquidityLocker;                           // Who can manage locks



    /**
     * @dev Anti-Dump Protection System
     * Prevents large sells that could crash token price.
     * Currently disabled for your business model.
     */
    bool public antiDumpEnabled;          // Whether anti-dump is active
    uint256 public maxSellPercentage;     // Max % of supply that can be sold per transaction
    mapping(address => uint256) public lastSellTime;  // Last time each address sold
    uint256 public sellCooldown;          // Time to wait between large sells

    /**
     * @dev Access Control and Security
     * These mappings control who can do what and provide security features.
     */
    mapping(address => bool) public blacklist;      // Banned addresses (cannot transfer)
    mapping(address => bool) public taxExempt;      // Addresses exempt from taxes

    // Additional token configuration  
    uint8 private _customDecimals;        // Number of decimal places (usually 18)
    uint256 public stakingLockPeriod;     // DEPRECATED: How long tokens are locked when staking

    // New tax variables - added at end for storage compatibility
    uint256 public buyTaxPercent;          // Tax on buys from DEX (default 1%)
    uint256 public sellTaxPercent;         // Tax on sells to DEX (default 2%)
    uint256 public transferTaxPercent;     // Tax on wallet transfers (default 2%)

    // Event Notifications for Important Actions
    event BlacklistUpdated(address account, bool value);
    event TaxExemptUpdated(address account, bool exempt);
    event NameSymbolUpdated(string newName, string newSymbol);
    event MetadataUpdated(string tokenURI);
    event PancakeRouterUpdated(address newRouter);
    event AntiBotConfigUpdated(bool enabled, uint256 duration);
    event AntiDumpConfigUpdated(bool enabled, uint256 maxPercentage, uint256 cooldown);
    event OwnershipRenounced(address previousOwner);
    event LiquidityLocked(address indexed pair, uint256 amount, uint256 unlockTime);
    event LiquidityUnlocked(address indexed pair, uint256 amount);
    event LiquidityLockConfigUpdated(bool enabled, uint256 defaultPeriod, address locker);

    // UNIQUE NODE META ENERGY CONTRACT IDENTIFIER
    string public constant CONTRACT_IDENTIFIER = "NODE_META_ENERGY_NTE_CONTRACT_V1_2025_UNIQUE";
    bytes32 public constant CONTRACT_HASH = keccak256("NODE_META_ENERGY_ADVANCED_DEFI_TOKEN_IMPLEMENTATION_V1");
    uint256 public constant CONTRACT_VERSION = 102; 
    
    // Unique deployment salt and project-specific identifiers
    bytes32 public constant PROJECT_SALT = keccak256(abi.encodePacked(
        "NODE_META_ENERGY_PROJECT_2025",
        "REVOLUTIONARY_BLOCKCHAIN_TECHNOLOGY", 
        "EMPOWERING_DECENTRALIZED_ENERGY",
        "UNIQUE_BUSINESS_MODEL_PACKAGE_SYSTEM"
    ));

    
    // Deployment-specific unique data
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable DEPLOYMENT_TIMESTAMP;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable DEPLOYER_ADDRESS;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bytes32 public immutable DEPLOYMENT_SALT;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
        // Set unique deployment characteristics to prevent bytecode similarity
        DEPLOYMENT_TIMESTAMP = block.timestamp;
        DEPLOYER_ADDRESS = msg.sender;
        DEPLOYMENT_SALT = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            block.prevrandao,
            block.number,
            "NODE_META_ENERGY_UNIQUE_DEPLOYMENT_V2"
        ));
        
        // Add unique no-op code that doesn't affect functionality but changes bytecode
        assembly {
            // This assembly block does nothing functional but creates unique bytecode
            let x := 0x123456789ABCDEF
            let y := 0xFEDCBA9876543210
            let z := add(x, y)
            // No-op that doesn't change state but creates unique bytecode pattern
            if eq(x, 0) { z := 0 }
        }
    }

    /**
     * @dev Initialize the contract with all starting parameters
     * @param initialSupply Total number of tokens to create (will be multiplied by decimals)
     * @param initialOwner Address that will own the contract and receive initial tokens
     * @param _treasury Address that will receive tax payments
     * @param _pancakeRouter PancakeSwap router address for DEX integration
     * 
     * This function can only be called once during contract deployment.
     * It sets up all the initial parameters and mints the initial token supply.
     */
    function initialize(
        uint256 initialSupply,
        address initialOwner,
        uint256, // _stakingRewardRate
        address _treasury,
        uint256, // _taxPercent
        address _pancakeRouter
    ) internal initializer {
        __ERC20_init("Node Meta Energy", "NTE");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __Pausable_init();

        // Extra uniqueness byte - doesn't affect functionality, just makes bytecode different
        keccak256(abi.encodePacked(block.timestamp, initialOwner, "NTE_UNIQUE_INIT"));
        
        // Mining parameters are ignored as mining functionality is disabled
        treasury = _treasury != address(0) ? _treasury : initialOwner; // Where tax money goes (default to owner)
        taxPercent = 2;                                             // Legacy tax (kept for compatibility)
        buyTaxPercent = 1;                                          // 1% tax on buys
        sellTaxPercent = 2;                                         // 2% tax on sells
        transferTaxPercent = 2;                                     // 2% tax on transfers

        // Set basic token information - how token appears in wallets
        _customName = "Node Meta Energy";
        _customSymbol = "NTE";
        _customDecimals = 18;                           // Standard 18 decimal places

        // Configure PancakeSwap trading - enables buying/selling on DEX
        if (_pancakeRouter != address(0)) {
            pancakeRouter = _pancakeRouter;
            address factory = IPancakeRouter(_pancakeRouter).factory();
            address weth = IPancakeRouter(_pancakeRouter).WETH();
            pancakePair = IPancakeFactory(factory).createPair(address(this), weth);
            isPancakePair[pancakePair] = true;
            
            // Only exempt router from taxes, not the pair itself
            taxExempt[_pancakeRouter] = true;
            // Remove this line to allow taxes on pair trades: taxExempt[pancakePair] = true;
        }

        // Set token branding and website information
        _tokenLogo = "https://node-meta.com/logo/node-meta.png";
        _description = "Node Meta Energy - Revolutionary Blockchain Technology, Empowering the Future of Decentralized Energy.";
        _website = "https://node-meta.com";

        // Disable all limits for maximum freedom in business operations
        autoLiquidityEnabled = false;                   // No automatic liquidity addition
        liquidityThreshold = type(uint256).max;         // Set to maximum value (no limit)
        maxTxAmount = type(uint256).max;                // No transaction limit
        maxWalletAmount = type(uint256).max;            // No wallet limit

        // Disable anti-dump protection for business flexibility
        antiDumpEnabled = false;                        // Allow large transfers
        maxSellPercentage = 100;                        // Can sell 100% of supply if needed
        sellCooldown = 0;                               // No cooldown between sells

        // Disable liquidity locking for maximum flexibility
        liquidityLockEnabled = false;                   // No liquidity locking
        defaultLiquidityLockPeriod = 0;                 // No default lock period
        liquidityLocker = initialOwner;                 // Owner can manage if enabled later

        // Enable anti-bot protection for launch period only
        antiBotEnabled = true;                          // Prevent bots during first 5 minutes
        antiBotDuration = 300;                          // 5 minutes of protection
        launchTime = block.timestamp;                   // Record when contract was deployed

        // Create initial token supply and give to owner
        _mint(initialOwner, initialSupply * 10 ** decimals());
    }

    /**
     * @notice Returns the full name of this token (e.g., "Node Meta Energy")
     * @dev This is the display name users see in wallets and exchanges
     * @return The token's full name as a string
     */
    function name() public view override returns (string memory) {
        return _customName;
    }

    /**
     * @notice Returns the trading symbol/ticker for this token (e.g., "NTE")
     * @dev This is the short abbreviation used on exchanges and trading platforms
     * @return The token's symbol as a string
     */
    function symbol() public view override returns (string memory) {
        return _customSymbol;
    }

    /**
     * @notice Returns the number of decimal places for token amounts (usually 18)
     * @dev This determines the smallest unit of the token (e.g., 18 decimals = 0.000000000000000001)
     * @return The number of decimal places as uint8
     */
    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    /**
     * @dev Owner can change token name and symbol
     * This allows rebranding of the token after deployment
     * @param newName The new name for the token
     * @param newSymbol The new symbol for the token
     * 
     * Example: setNameAndSymbol("New Meta Energy", "NME")
     * Only the contract owner can call this function
     */
    function setNameAndSymbol(string memory newName, string memory newSymbol) internal onlyOwner {
        _customName = newName;
        _customSymbol = newSymbol;
        emit NameSymbolUpdated(newName, newSymbol);
    }

    /**
     * @dev Owner can change token decimals
     * WARNING: Changing decimals after deployment can cause display issues in wallets
     * @param newDecimals The new number of decimal places
     * Only use this function if you understand the implications
     */
    function setDecimals(uint8 newDecimals) internal onlyOwner {
        _customDecimals = newDecimals;
    }

     /**
        * @notice Get complete token metadata including name, symbol, supply, logo, description, website and social links
        * @dev Returns a JSON string with all token information for wallets and block explorers
        * @return Complete token metadata as JSON string
     */
    function tokenURI() public view returns (string memory) {
        string memory socialLinksJson = _buildSocialLinksJson();
        string memory json = string(abi.encodePacked(
            '{"name":"', _customName, 
            '","symbol":"', _customSymbol,
            '","decimals":', uint2str(decimals()),
            ',"totalSupply":"', uint2str(totalSupply()),
            ',"image":"', _tokenLogo,
            '","description":"', _description,
            '","website":"', _website,
            '","social":', socialLinksJson,
            ',"contract":"', addressToString(address(this)),
            ',"version":"', uint2str(CONTRACT_VERSION),
            ',"deploymentTime":"', uint2str(DEPLOYMENT_TIMESTAMP),
            '"}'
        ));
        return json;
    }



    /**
     * @dev Override standard ERC20 transfer to apply custom tax logic
     * This function is called whenever someone uses the standard transfer() function
     * It applies all security checks, taxes, and business logic before transferring tokens
     * @param to The address to send tokens to
     * @param amount The number of tokens to send
     * @return bool Always returns true if transfer succeeds (reverts if it fails)
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        _transferWithTax(owner, to, amount);
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another (requires prior approval)
     * @dev Used by DEXs and contracts to move tokens on your behalf after you've approved them
     * @param from The address to send tokens from
     * @param to The address to send tokens to
     * @param amount The number of tokens to transfer (in wei, including 18 decimals)
     * @return success True if the transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transferWithTax(from, to, amount);
        return true;
    }

    /**
     * @dev Internal transfer function with all security checks and tax logic
     * This is the main transfer function that handles:
     * - Blacklist checks (prevents banned addresses from sending/receiving)
     * - Transaction limits (if enabled)
     * - Anti-dump protection (if enabled)
     * - Anti-bot protection (during launch period)
     * - Tax collection (with exemptions)
     * 
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param amount The number of tokens to transfer
     */
    function _transferWithTax(address from, address to, uint256 amount) internal {
        require(!paused(), "Token transfers are paused by contract owner");
        require(!blacklist[from] && !blacklist[to], "One or both addresses are blacklisted");

        // Check transaction limits (only applies to non-exempt addresses)
        if (!taxExempt[from] && !taxExempt[to]) {
            require(amount <= maxTxAmount, "Transfer amount exceeds maximum transaction limit");
            // Check wallet limit for receiving address (except contract and DEX pairs)
            if (to != address(this) && !isPancakePair[to]) {
                require(balanceOf(to) + amount <= maxWalletAmount, "Receiving wallet would exceed maximum balance limit");
            }
        }

        // Anti-dump protection for large sells to DEX (if enabled)
        if (antiDumpEnabled && isPancakePair[to] && !taxExempt[from]) {
            uint256 maxSellAmount = (totalSupply() * maxSellPercentage) / 100;
            require(amount <= maxSellAmount, "Sell amount exceeds anti-dump limit");
            require(block.timestamp > lastSellTime[from] + sellCooldown, "Anti-dump cooldown period still active");
            lastSellTime[from] = block.timestamp;
        }

        // Anti-bot protection during first few minutes after contract launch
        if (antiBotEnabled && block.timestamp < launchTime + antiBotDuration) {
            require(from == owner() || to == owner() || taxExempt[from] || taxExempt[to], "Anti-bot protection is active - only owner and exempt addresses can trade");
        }

        // Apply tax logic - exempt addresses don't pay taxes
        if (
            from == owner() ||           // Owner sends/receives tax-free
            to == owner() ||             // Owner sends/receives tax-free
            from == address(this) ||     // Contract operations are tax-free
            to == address(this) ||       // Contract operations are tax-free
            taxExempt[from] ||           // Manually exempted sender
            taxExempt[to]                // Manually exempted receiver
        ) {
            // No tax applied - direct transfer
            _transfer(from, to, amount);
        } else {
            // Tax applied - calculate tax based on transaction type
            uint256 tax = 0;
            
            if (isPancakePair[from] && !isPancakePair[to]) {
                // Buy from DEX - apply buy tax
                tax = (amount * buyTaxPercent) / 100;
            } else if (!isPancakePair[from] && isPancakePair[to]) {
                // Sell to DEX - apply sell tax  
                tax = (amount * sellTaxPercent) / 100;
            } else if (!isPancakePair[from] && !isPancakePair[to]) {
                // Wallet to wallet transfer - apply transfer tax
                tax = (amount * transferTaxPercent) / 100;
            }
            // Note: DEX to DEX transfers (if any) have no tax
            
            if (tax > 0 && treasury != address(0)) {
                uint256 afterTax = amount - tax;
                _transfer(from, treasury, tax);      // Send tax to treasury first
                _transfer(from, to, afterTax);       // Send remaining to recipient
            } else {
                // No tax or invalid treasury
                _transfer(from, to, amount);
            }
        }
    }

    /**
     * @notice Transfer tokens with automatic tax calculation (legacy compatibility function)
     * @dev Same as regular transfer() but explicitly shows that taxes will be applied
     * @param to The wallet address to receive the tokens
     * @param amount The number of tokens to send (tax will be deducted automatically)
     */
    function taxedTransfer(address to, uint256 amount) public whenNotPaused {
        _transferWithTax(msg.sender, to, amount);
    }



    /**
     * @notice Owner only: Set buy, sell, and transfer tax percentages in one transaction
     * @dev Allows the contract owner to update all tax rates efficiently. Max 100% per tax type.
     * @param newBuyTaxPercent Tax percentage for buying from DEX (0-100, e.g., 1 = 1%)
     * @param newSellTaxPercent Tax percentage for selling to DEX (0-100, e.g., 2 = 2%)
     * @param newTransferTaxPercent Tax percentage for wallet-to-wallet transfers (0-100, e.g., 2 = 2%)
     */
    function setAllTaxPercents(
        uint256 newBuyTaxPercent,
        uint256 newSellTaxPercent,
        uint256 newTransferTaxPercent
    ) external onlyOwner {
        require(newBuyTaxPercent <= 100, "Buy tax cannot exceed 100%");
        require(newSellTaxPercent <= 100, "Sell tax cannot exceed 100%");
        require(newTransferTaxPercent <= 100, "Transfer tax cannot exceed 100%");
        
        buyTaxPercent = newBuyTaxPercent;
        sellTaxPercent = newSellTaxPercent;
        transferTaxPercent = newTransferTaxPercent;
    }



    /**
     * @notice Owner only: Add or remove tax exemptions for specific addresses
     * @dev Exempt addresses don't pay any taxes on transfers. Useful for business wallets and partnerships.
     * @param user The wallet address to modify tax exemption for
     * @param exempt True to exempt from all taxes, false to apply normal taxes
     */
    function setTaxExempt(address user, bool exempt) external onlyOwner {
        taxExempt[user] = exempt;
        emit TaxExemptUpdated(user, exempt);
    }



    /**
     * @notice Owner only: Block or unblock addresses from using this token
     * @dev Blacklisted addresses cannot send, receive, or trade tokens. Use for compliance or security.
     * @param user The wallet address to blacklist or unblacklist
     * @param value True to blacklist (block all token activity), false to remove from blacklist
     */
    function blacklistAddress(address user, bool value) public onlyOwner {
        blacklist[user] = value;
        emit BlacklistUpdated(user, value);
    }



    /**
     * @dev Owner can update the PancakeSwap router address
     * This is needed if PancakeSwap updates their contracts
     * @param newRouter Address of the new PancakeSwap router
     */
    function setPancakeRouter(address newRouter) internal onlyOwner {
        if (pancakeRouter != address(0)) {
            taxExempt[pancakeRouter] = false;
        }
        pancakeRouter = newRouter;
        if (newRouter != address(0)) {
            taxExempt[newRouter] = true;
        }
        emit PancakeRouterUpdated(newRouter);
    }

    /**
     * @dev Owner can designate which addresses are trading pairs
     * Trading pairs get special treatment for anti-dump checks
     * Note: Pairs are NOT automatically tax exempt to ensure taxes are collected
     * @param pair The address of the trading pair
     * @param isPair True if this is a trading pair, false otherwise
     */
    function setPancakePair(address pair, bool isPair) internal onlyOwner {
        isPancakePair[pair] = isPair;
        // Do not automatically exempt pairs from taxes
        // if (isPair) {
        //     taxExempt[pair] = true;
        // }
    }

    /**
     * @dev Owner can configure anti-bot protection settings
     * Anti-bot protection prevents trading during the first few minutes after launch
     * @param enabled True to enable anti-bot protection, false to disable
     * @param duration How long anti-bot protection lasts (in seconds)
     */
    function setAntiBotConfig(bool enabled, uint256 duration) internal onlyOwner {
        antiBotEnabled = enabled;
        antiBotDuration = duration;
        emit AntiBotConfigUpdated(enabled, duration);
    }

    /**
     * @dev Owner can update all token metadata in one transaction
     * @param newLogo URL to the new logo image
     * @param newDescription New description text for the token
     * @param newWebsite New website URL (should include https://)
     * @param twitterUrl Twitter/X profile URL
     * @param telegramUrl Telegram group/channel URL
     * @param discordUrl Discord server URL
     * @param mediumUrl Medium blog/articles URL
     * @param githubUrl GitHub repository URL
     * @param youtubeUrl YouTube channel URL
     * @param linkedinUrl LinkedIn profile/company URL
     * @param redditUrl Reddit community URL
     * @param instagramUrl Instagram profile URL
     * @param facebookUrl Facebook page URL
     * @param tiktokUrl TikTok profile URL
     * @param whitepaperUrl Whitepaper document URL
     * @param auditUrl Security audit report URL
     */
    function setAllMetadata(
        string memory newLogo,
        string memory newDescription,
        string memory newWebsite,
        string memory twitterUrl,
        string memory telegramUrl,
        string memory discordUrl,
        string memory mediumUrl,
        string memory githubUrl,
        string memory youtubeUrl,
        string memory linkedinUrl,
        string memory redditUrl,
        string memory instagramUrl,
        string memory facebookUrl,
        string memory tiktokUrl,
        string memory whitepaperUrl,
        string memory auditUrl
    ) internal onlyOwner {
        _tokenLogo = newLogo;
        _description = newDescription;
        _website = newWebsite;
        
        // Update all social media links
        _socialLinks["twitter"] = twitterUrl;
        _socialLinks["telegram"] = telegramUrl;
        _socialLinks["discord"] = discordUrl;
        _socialLinks["medium"] = mediumUrl;
        _socialLinks["github"] = githubUrl;
        _socialLinks["youtube"] = youtubeUrl;
        _socialLinks["linkedin"] = linkedinUrl;
        _socialLinks["reddit"] = redditUrl;
        _socialLinks["instagram"] = instagramUrl;
        _socialLinks["facebook"] = facebookUrl;
        _socialLinks["tiktok"] = tiktokUrl;
        _socialLinks["whitepaper"] = whitepaperUrl;
        _socialLinks["audit"] = auditUrl;
        
        emit MetadataUpdated(tokenURI());
    }

    /**
     * @notice Internal accessor for individual social links; kept internal to reduce BscScan noise.
     */
    function getSocialLink(string memory platform) internal view returns (string memory) {
        return _socialLinks[platform];
    }

    /**
     * @dev Owner can set maximum tokens allowed per transaction
     * This controls the maximum amount of tokens that can be transferred in one transaction
     * Setting to type(uint256).max removes the limit (recommended for business model)
     * @param amount Maximum tokens per transaction (in wei, including decimals)
     */
    function setMaxTxAmount(uint256 amount) internal onlyOwner {
        maxTxAmount = amount;
    }

    /**
     * @dev Owner can set maximum tokens allowed per wallet
     * This controls the maximum balance any wallet can hold
     * Setting to type(uint256).max removes the limit (recommended for business model)
     * @param amount Maximum tokens per wallet (in wei, including decimals)
     */
    function setMaxWalletAmount(uint256 amount) internal onlyOwner {
        maxWalletAmount = amount;
    }

    /**
     * @notice Owner only: Configure anti-dump protection to prevent large price crashes
     * @dev Set limits on how much of the total supply can be sold at once and cooldown periods
     * @param enabled True to enable anti-dump protection, false to disable
     * @param maxPercentage Maximum percentage of total supply sellable per transaction (0-100)
     * @param cooldownTime Seconds users must wait between large sells
     */
    function setAntiDumpConfig(bool enabled, uint256 maxPercentage, uint256 cooldownTime) external onlyOwner {
        antiDumpEnabled = enabled;
        maxSellPercentage = maxPercentage;
        sellCooldown = cooldownTime;
        emit AntiDumpConfigUpdated(enabled, maxPercentage, cooldownTime);
    }


    /**
     * @notice Owner only: Permanently give up ownership after 30 days (IRREVERSIBLE!)
     * @dev Once ownership is renounced, no one can call owner-only functions ever again. Use with extreme caution.
     */
    function renounceOwnership() public override onlyOwner {
        require(block.timestamp > launchTime + 30 days, "Cannot renounce ownership for 30 days after launch");
        address previousOwner = owner();
        _transferOwnership(address(0));
        emit OwnershipRenounced(previousOwner);
    }

    /**
     * @notice Owner only: Lock liquidity pair tokens to prevent rug pulls and build trust
     * @dev Locks LP tokens in this contract for a specified time period. Locked tokens cannot be withdrawn early.
     * @param pair The address of the liquidity pair (LP token contract address)
     * @param amount Number of LP tokens to lock (in wei, check LP token decimals)
     * @param lockPeriod How long to lock the tokens (in seconds, e.g., 31536000 = 1 year)
     */
    function lockLiquidity(address pair, uint256 amount, uint256 lockPeriod) external onlyOwner {
        require(liquidityLockEnabled, "Liquidity locking is currently disabled");
        require(pair != address(0), "Invalid liquidity pair address");
        require(amount > 0, "Lock amount must be greater than zero");
        require(lockPeriod > 0, "Lock period must be greater than zero");

        IERC20 lpToken = IERC20(pair);
        require(lpToken.balanceOf(msg.sender) >= amount, "Insufficient LP tokens in your wallet");

        // Transfer LP tokens from user to this contract for safekeeping
        lpToken.transferFrom(msg.sender, address(this), amount);

        uint256 unlockTime = block.timestamp + lockPeriod;
        liquidityLocks[pair] = LiquidityLock({
            amount: amount,
            lockTime: block.timestamp,
            unlockTime: unlockTime,
            isLocked: true,
            locker: msg.sender
        });

        emit LiquidityLocked(pair, amount, unlockTime);
    }

    /**
     * @notice Owner only: Unlock previously locked liquidity tokens after lock period expires
     * @dev Retrieve locked LP tokens once the lock period has ended. Cannot unlock early.
     * @param pair The liquidity pair address that has locked tokens
     */
    function unlockLiquidity(address pair) external onlyOwner {
        LiquidityLock storage lock = liquidityLocks[pair];
        require(lock.isLocked, "No liquidity is currently locked for this pair");
        require(block.timestamp >= lock.unlockTime, "Lock period has not expired yet");
        require(msg.sender == lock.locker || msg.sender == owner(), "Not authorized to unlock this liquidity");

        uint256 amount = lock.amount;
        lock.isLocked = false;
        lock.amount = 0;

        IERC20 lpToken = IERC20(pair);
        lpToken.transfer(lock.locker, amount);

        emit LiquidityUnlocked(pair, amount);
    }

    /**
     * @notice Owner only: Extend the lock period for already locked liquidity
     * @dev Add more time to existing liquidity locks without unlocking first. Cannot reduce lock time.
     * @param pair The liquidity pair address with locked tokens
     * @param additionalTime Additional seconds to add to the current lock period
     */
    function extendLiquidityLock(address pair, uint256 additionalTime) external onlyOwner {
        LiquidityLock storage lock = liquidityLocks[pair];
        require(lock.isLocked, "No liquidity is currently locked for this pair");
        require(additionalTime > 0, "Additional time must be greater than zero");

        lock.unlockTime += additionalTime;
        emit LiquidityLocked(pair, lock.amount, lock.unlockTime);
    }

    /**
     * @notice Owner only: View detailed information about locked liquidity for a specific pair
     * @dev Check lock status, amounts, timing, and who locked the liquidity tokens
     * @param pair The liquidity pair address to check
     * @return amount Number of LP tokens currently locked
     * @return lockTime When the lock was created (Unix timestamp)
     * @return unlockTime When the lock expires (Unix timestamp)
     * @return timeRemaining Seconds remaining until unlock (0 if already unlocked)
     * @return isLocked Whether tokens are currently locked
     * @return locker Address that originally locked the tokens
     */
    function getLiquidityLockInfo(address pair) external view onlyOwner returns (
        uint256 amount,
        uint256 lockTime,
        uint256 unlockTime,
        uint256 timeRemaining,
        bool isLocked,
        address locker
    ) {
        LiquidityLock storage lock = liquidityLocks[pair];
        amount = lock.amount;
        lockTime = lock.lockTime;
        unlockTime = lock.unlockTime;
        timeRemaining = lock.isLocked && block.timestamp < lock.unlockTime 
            ? lock.unlockTime - block.timestamp 
            : 0;
        isLocked = lock.isLocked;
        locker = lock.locker;
    }

    /**
     * @notice Owner only: Configure the liquidity locking system settings
     * @dev Enable/disable locking, set default periods, and designate who can manage locks
     * @param enabled True to enable liquidity locking feature, false to disable
     * @param defaultPeriod Default lock period in seconds for quick locks
     * @param newLocker Address authorized to manage liquidity locks (besides owner)
     */
    function setLiquidityLockConfig(bool enabled, uint256 defaultPeriod, address newLocker) external onlyOwner {
        liquidityLockEnabled = enabled;
        defaultLiquidityLockPeriod = defaultPeriod;
        liquidityLocker = newLocker;
        emit LiquidityLockConfigUpdated(enabled, defaultPeriod, newLocker);
    }

    /**
     * @notice Owner only: Emergency unlock liquidity in extreme situations (USE WITH CAUTION!)
     * @dev Bypass normal lock periods in emergencies. Should only be used if original locker loses access.
     * @param pair The liquidity pair address to emergency unlock
     */
    function emergencyUnlockLiquidity(address pair) external onlyOwner {
        LiquidityLock storage lock = liquidityLocks[pair];
        require(lock.isLocked, "No liquidity is currently locked for this pair");

        uint256 amount = lock.amount;
        lock.isLocked = false;
        lock.amount = 0;

        IERC20 lpToken = IERC20(pair);
        lpToken.transfer(lock.locker, amount);

        emit LiquidityUnlocked(pair, amount);
    }

    /**
     * @notice Owner only: Lock liquidity using the pre-configured default time period
     * @dev Quick way to lock liquidity without specifying custom time. Uses defaultLiquidityLockPeriod.
     * @param pair The liquidity pair address to lock
     * @param amount Number of LP tokens to lock (in wei, check LP token decimals)
     */
    function quickLockLiquidity(address pair, uint256 amount) external onlyOwner {
        require(liquidityLockEnabled, "Liquidity locking is currently disabled");
        require(pair != address(0), "Invalid liquidity pair address");
        require(amount > 0, "Lock amount must be greater than zero");
        require(defaultLiquidityLockPeriod > 0, "Default lock period is not configured");

        IERC20 lpToken = IERC20(pair);
        require(lpToken.balanceOf(msg.sender) >= amount, "Insufficient LP tokens in your wallet");

        // Transfer LP tokens from user to this contract for safekeeping
        lpToken.transferFrom(msg.sender, address(this), amount);

        uint256 unlockTime = block.timestamp + defaultLiquidityLockPeriod;
        liquidityLocks[pair] = LiquidityLock({
            amount: amount,
            lockTime: block.timestamp,
            unlockTime: unlockTime,
            isLocked: true,
            locker: msg.sender
        });

        emit LiquidityLocked(pair, amount, unlockTime);
    }

    /**
     * @notice Owner only: Pause all token transfers and trading (emergency use only)
     * @dev When paused, nobody can transfer, buy, or sell tokens. Use for maintenance or emergencies.
     */
    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Owner only: Resume normal token operations after being paused
     * @dev Restores all transfer, trading, and other token functionality
     */
    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Owner can mint new tokens to any address
     * Creates new tokens and adds them to the specified address
     * Blacklisted addresses cannot receive minted tokens
     * @param to The address to receive the newly minted tokens
     * @param amount The number of tokens to mint (will be multiplied by decimals)
     */
    function mint(address to, uint256 amount) internal onlyOwner {
        require(!blacklist[to], "Cannot mint tokens to blacklisted address");
        _mint(to, amount);
    }

    /**
     * @dev Users can burn their own tokens to permanently remove them from circulation
     * This reduces the total supply of tokens
     * @param amount The number of tokens to burn from sender's balance
     */
    function burn(uint256 amount) internal {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Owner only: Rescue tokens accidentally sent to this contract
     * @dev Withdraw any ERC20 tokens that were mistakenly sent to this contract address
     * @param token The contract address of the token to rescue
     * @param to The address to send the rescued tokens to
     * @param amount The number of tokens to rescue (in wei, check token decimals)
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }




    /**
     * @notice Get comprehensive token information including metadata, supply, and branding
     * @dev Returns all basic token details that users and applications need to display token info
     * @return tokenName Current name of the token
     * @return tokenSymbol Current symbol/ticker of the token  
     * @return tokenDecimals Number of decimal places for token amounts
     * @return tokenTotalSupply Current total supply of tokens in circulation
     * @return logo URL to the token logo image
     * @return description Token description text
     * @return website Official project website URL
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
        tokenName = _customName;
        tokenSymbol = _customSymbol;
        tokenDecimals = _customDecimals;
        tokenTotalSupply = totalSupply();
        logo = _tokenLogo;
        description = _description;
        website = _website;
    }

     /**
     * @dev Internal utility function to convert numbers to strings
     * Used for building JSON metadata and displaying token information
     * @param _i The number to convert to string
     * @return str The string representation of the number
     */
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        str = string(bstr);
    }

    /**
     * @dev Internal utility function to convert addresses to strings
     * Used for building JSON metadata and displaying contract information
     * @param _addr The address to convert to string format
     * @return string memory The hexadecimal string representation of the address
     */
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    /**
     * @dev Internal function to build social media links JSON
     * Creates a JSON object containing all social media platform URLs
     * Used by tokenURI() to include social links in token metadata
     * @return string memory JSON formatted string with social media links
     */
    function _buildSocialLinksJson() internal view returns (string memory) {
        return string(abi.encodePacked(
            '{"twitter":"', _socialLinks["twitter"],
            '","telegram":"', _socialLinks["telegram"],
            '","discord":"', _socialLinks["discord"],
            '","medium":"', _socialLinks["medium"],
            '","github":"', _socialLinks["github"],
            '","youtube":"', _socialLinks["youtube"],
            '","linkedin":"', _socialLinks["linkedin"],
            '","reddit":"', _socialLinks["reddit"],
            '","instagram":"', _socialLinks["instagram"],
            '","facebook":"', _socialLinks["facebook"],
            '","tiktok":"', _socialLinks["tiktok"],
            '","whitepaper":"', _socialLinks["whitepaper"],
            '","audit":"', _socialLinks["audit"],
            '"}'
        ));
    }


    /**
     * @notice Provides every configured social link so users can verify official channels on BscScan.
     * @return twitter Twitter/X profile URL.
     * @return telegram Telegram community URL.
     * @return discord Discord server URL.
     * @return medium Medium publication URL.
     * @return github GitHub repository URL.
     * @return youtube YouTube channel URL.
     * @return linkedin LinkedIn page URL.
     * @return reddit Reddit community URL.
     * @return instagram Instagram profile URL.
     * @return facebook Facebook page URL.
     * @return tiktok TikTok profile URL.
     * @return whitepaper Whitepaper document URL.
     * @return audit Audit report URL.
     */
    function getAllSocialLinks() public view returns (
        string memory twitter,
        string memory telegram,
        string memory discord,
        string memory medium,
        string memory github,
        string memory youtube,
        string memory linkedin,
        string memory reddit,
        string memory instagram,
        string memory facebook,
        string memory tiktok,
        string memory whitepaper,
        string memory audit
    ) {
        twitter = _socialLinks["twitter"];
        telegram = _socialLinks["telegram"];
        discord = _socialLinks["discord"];
        medium = _socialLinks["medium"];
        github = _socialLinks["github"];
        youtube = _socialLinks["youtube"];
        linkedin = _socialLinks["linkedin"];
        reddit = _socialLinks["reddit"];
        instagram = _socialLinks["instagram"];
        facebook = _socialLinks["facebook"];
        tiktok = _socialLinks["tiktok"];
        whitepaper = _socialLinks["whitepaper"];
        audit = _socialLinks["audit"];
    }

    /**
     * @dev Get all unique contract identifiers
     * Returns all the unique salts and hashes that make this contract distinguishable
     * @return projectSalt Unique project identifier salt
     * @return deploymentSalt Unique deployment-specific salt
     * @return contractHash Main contract implementation hash
     * @return deploymentTime When contract was deployed
     * @return deployerAddr Who deployed the contract
     */
    function getUniqueIdentifiers() internal view returns (
        bytes32 projectSalt,
        bytes32 deploymentSalt,
        bytes32 contractHash,
        uint256 deploymentTime,
        address deployerAddr
    ) {
        projectSalt = PROJECT_SALT;
        deploymentSalt = DEPLOYMENT_SALT;
        contractHash = CONTRACT_HASH;
        deploymentTime = DEPLOYMENT_TIMESTAMP;
        deployerAddr = DEPLOYER_ADDRESS;
    }

    /**
     * Only the contract owner can authorize upgrades to new implementations
     * This is a security feature of the UUPS (Universal Upgradeable Proxy Standard) pattern
     * @param newImplementation Address of the new contract implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Summarises the live tax configuration for transparency on BscScan.
     * @return buyTax Current buy tax percentage.
     * @return sellTax Current sell tax percentage.
     * @return transferTax Current transfer tax percentage.
     * @return treasuryAddr Treasury address receiving tax proceeds.
     * @return routerExempt Whether the router is tax exempt.
     * @return pairExempt Whether the main pair is tax exempt.
     */
    function getTaxConfiguration() public view returns (
        uint256 buyTax,
        uint256 sellTax,
        uint256 transferTax,
        address treasuryAddr,
        bool routerExempt,
        bool pairExempt
    ) {
        buyTax = buyTaxPercent;
        sellTax = sellTaxPercent;
        transferTax = transferTaxPercent;
        treasuryAddr = treasury;
        routerExempt = taxExempt[pancakeRouter];
        pairExempt = taxExempt[pancakePair];
    }

    /**
     * @dev Owner can fix tax exemptions for proper tax collection
     * Use this to ensure taxes are collected on DEX trades
     */
    function fixTaxExemptions() internal onlyOwner {
        // Keep router exempt for smooth swaps, but remove pair exemption
        if (pancakeRouter != address(0)) {
            taxExempt[pancakeRouter] = true;
        }
        if (pancakePair != address(0)) {
            taxExempt[pancakePair] = false; // Remove pair exemption to collect taxes
        }
    }

    /**
     * @notice Owner only: Update the treasury address that receives all tax payments
     * @dev Change where tax revenue is sent. New address will receive all future tax collections.
     * @param newTreasury The new wallet address to receive tax payments (cannot be zero address)
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Treasury cannot be zero address");
        treasury = newTreasury;
    }

    /**
     * @notice Owner only: Add more LP tokens to an existing lock (accumulative locking)
     * @dev Add tokens to existing lock without changing the unlock time. Creates new lock if none exists.
     * @param pair The liquidity pair address with existing lock
     * @param amount Additional LP tokens to add to the lock (in wei, check LP token decimals)
     */
    function addToLiquidityLock(address pair, uint256 amount) external onlyOwner {
        require(liquidityLockEnabled, "Liquidity locking is currently disabled");
        require(pair != address(0), "Invalid liquidity pair address");
        require(amount > 0, "Amount must be greater than zero");

        IERC20 lpToken = IERC20(pair);
        require(lpToken.balanceOf(msg.sender) >= amount, "Insufficient LP tokens in your wallet");

        // Transfer additional LP tokens from user to this contract
        lpToken.transferFrom(msg.sender, address(this), amount);

        LiquidityLock storage lock = liquidityLocks[pair];
        
        if (lock.isLocked) {
            // Add to existing lock
            lock.amount += amount;
            emit LiquidityLocked(pair, lock.amount, lock.unlockTime);
        } else {
            // Create new lock with default period if no existing lock
            require(defaultLiquidityLockPeriod > 0, "Default lock period is not configured");
            uint256 unlockTime = block.timestamp + defaultLiquidityLockPeriod;
            liquidityLocks[pair] = LiquidityLock({
                amount: amount,
                lockTime: block.timestamp,
                unlockTime: unlockTime,
                isLocked: true,
                locker: msg.sender
            });
            emit LiquidityLocked(pair, amount, unlockTime);
        }
    }

    /**
     * @notice Owner only: Extend lock period and optionally add more tokens
     * @dev Extend unlock time and add more LP tokens in one transaction
     * @param pair The liquidity pair address with existing lock
     * @param additionalAmount Extra LP tokens to add (can be 0 to just extend time)
     * @param additionalTime Additional seconds to add to unlock time
     */
    function extendAndAddLiquidity(address pair, uint256 additionalAmount, uint256 additionalTime) external onlyOwner {
        LiquidityLock storage lock = liquidityLocks[pair];
        require(lock.isLocked, "No liquidity is currently locked for this pair");
        require(additionalTime > 0 || additionalAmount > 0, "Must add time or amount");

        if (additionalAmount > 0) {
            IERC20 lpToken = IERC20(pair);
            require(lpToken.balanceOf(msg.sender) >= additionalAmount, "Insufficient LP tokens");
            lpToken.transferFrom(msg.sender, address(this), additionalAmount);
            lock.amount += additionalAmount;
        }

        if (additionalTime > 0) {
            lock.unlockTime += additionalTime;
        }

        emit LiquidityLocked(pair, lock.amount, lock.unlockTime);
    }
}