// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title INTE
 * @notice Interface for interacting with the main NTE token contract to query roles,
 *         verify signatures, perform token transfers, and query rescue vault details.
 */
interface INTE {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function emergencyRescueVault() external view returns (address);
    function launchTime() external view returns (uint256);
}

/**
 * @title IERC20
 * @notice Minimal ERC20 interface used for emergency stuck-funds recovery operations.
 */
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/**
 * @title NTECategoryManager
 * @notice Decoupled contract that manages NTE transaction category bookkeeping,
 *         signer authorizations, signature verification, and statistics.
 *         Permission checks are derived dynamically from the main NTE token contract.
 */

/*
 * ═══════════════════════════════════════════════════════════════════════════
 * ERROR CODES - Making Sense of Reverts
 * ═══════════════════════════════════════════════════════════════════════════
 * We use descriptive prefixes so you know exactly why a transaction failed.
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ PERMISSIONS & OWNERSHIP [AUTH_*]                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 * AUTH_INVALID     Invalid role or signature    AUTH_ALREADY_SET   Signer is already authorized
 * AUTH_NOT_SET     Signer isn't authorized      AUTH_ZERO_ADDR     Signer can't be zero address
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ SYSTEM & SECURITY [SYS_*, SEC_*]                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 * SEC_REENTRY      No reentrancy allowed
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ GENERAL CHECKS & STRINGS [ADDR_*, STR_*]                                │
 * └─────────────────────────────────────────────────────────────────────────┘
 * ADDR_ZERO        Zero address not allowed     STR_TOO_LONG       String exceeds max length
 * ADDR_FROM_ZERO   Sending from zero address     STR_EMPTY          String cannot be empty
 * ADDR_TO_ZERO     Sending to zero address
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ TRANSACTION CHECKS [TXN_*, SIG_*, TRANSFER_*]                           │
 * └─────────────────────────────────────────────────────────────────────────┘
 * TXN_AMOUNT_ZERO  Need to send more than 0      SIG_EXPIRED        Signature past deadline
 * TXN_REPLAY       This transaction was used     TRANSFER_FAIL      Token transfer failed
 * TXN_OVERFLOW     Math overflow detected
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ CATEGORIES [CAT_*]                                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * CAT_INVALID      This category doesn't exist   CAT_DISABLED       Category is turned off
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ EMERGENCY RESCUE [EMG_*]                                                │
 * └─────────────────────────────────────────────────────────────────────────┘
 * EMG_TRANSFER_FAIL Token transfer failed         EMG_INVALID_RECIP  Recipient is invalid
 * EMG_INVALID_TOKEN Token address is invalid      EMG_INSUF_BAL_BNB  Not enough BNB
 * EMG_INSUF_BAL    Not enough balance            EMG_BNB_FAIL       BNB transfer failed
 * EMG_WAIT_30D     Wait 30 days after launch
 *
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract NTECategoryManager {
    /// @notice Reference to the main NTE token contract
    INTE public immutable nte;
    /// @notice Governance role identifier
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    /// @notice Security role identifier
    bytes32 public constant SECURITY_ROLE = keccak256("SECURITY_ROLE");
    /// @notice Maximum length for category names, references, and memos (256 characters)
    uint256 private constant MAX_STRING_LENGTH = 256;
    /// @notice Safety lock duration after launch to prevent premature native currency rescue
    uint256 private constant OWNERSHIP_LOCK_PERIOD = 30 days;
    /// @notice Reentrancy guard status variable
    bool private _entered;


    /// @notice Mapping of authorized off-chain signature verification addresses
    mapping(address => bool) public isAuthSigner;
    /// @notice Cumulative transaction count per category ID
    mapping(uint8 => uint256) public categoryTransactionCount;
    /// @notice Cumulative token volume transferred per category ID
    mapping(uint8 => uint256) public categoryTotalVolume;
    /// @notice Personal transaction count per user address per category ID
    mapping(address => mapping(uint8 => uint256)) public userCategoryCount;
    /// @notice Personal token volume per user address per category ID
    mapping(address => mapping(uint8 => uint256)) public userCategoryVolume;
    /// @notice Active status flags per category ID
    mapping(uint8 => bool) public categoryEnabled;
    /// @notice Sequential transaction nonce per user address to prevent signature replays
    mapping(address => uint256) public userCategorizedNonce;
    /// @notice Display name per category ID
    mapping(uint8 => string) public categoryNames;
    /// @notice Count of categories created in the system
    uint8 public totalCategories;

    // ===================================================
    // EVENTS
    // ===================================================

    /// @notice Emitted when a new off-chain verification signer is added
    event AuthSignerAdded(address indexed authAddress);
    /// @notice Emitted when an off-chain verification signer is removed
    event AuthSignerRemoved(address indexed authAddress);
    /// @notice Emitted when a category's enabled/disabled status is updated
    event CategoryStatusUpdated(uint8 indexed category, bool enabled);
    /// @notice Emitted when category statistics are updated (transaction count and volume)
    event CategoryStatsUpdated(uint8 indexed category, uint256 txCount, uint256 totalVolume);
    /// @notice Emitted when a new category is added
    event CategoryAdded(uint8 indexed categoryId, string name);
    /// @notice Emitted when a category name is updated
    event CategoryUpdated(uint8 indexed categoryId, string name);
    /// @notice Emitted when a categorized transaction is successfully processed
    event TransactionProcessed(address indexed from, address indexed to, uint256 value, uint8 category, string referenceId, string memo);
    /// @notice Emitted when stuck ERC20 tokens are recovered by governance
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when BNB is recovered by governance
    event EmergencyBNBWithdraw(address indexed to, uint256 amount);

    // ===================================================
    // ERRORS
    // ===================================================

    /// @notice Thrown when a reentrant call is detected
    error SEC_REENTRY();
    /// @notice Thrown when caller lacks the required administrative role or has an invalid signature
    error AUTH_INVALID();
    /// @notice Thrown when an input address is the zero address
    error ADDR_ZERO();
    /// @notice Thrown when the transfer source (from) is the zero address
    error ADDR_FROM_ZERO();
    /// @notice Thrown when the transfer destination (to) is the zero address
    error ADDR_TO_ZERO();
    /// @notice Thrown when the transaction amount is zero
    error TXN_AMOUNT_ZERO();
    /// @notice Thrown when the signature's deadline timestamp has passed
    error SIG_EXPIRED();
    /// @notice Thrown when a transaction signature is replayed
    error TXN_REPLAY();
    /// @notice Thrown when a signer is already authorized
    error AUTH_ALREADY_SET();
    /// @notice Thrown when a signer was not previously authorized
    error AUTH_NOT_SET();
    /// @notice Thrown when trying to authorize the zero address
    error AUTH_ZERO_ADDR();
    /// @notice Thrown when category ID is invalid or doesn't exist
    error CAT_INVALID();
    /// @notice Thrown when trying to use a disabled category
    error CAT_DISABLED();
    /// @notice Thrown when string parameter exceeds MAX_STRING_LENGTH
    error STR_TOO_LONG();
    /// @notice Thrown when a required string parameter is empty
    error STR_EMPTY();
    /// @notice Thrown when the external NTE token transfer fails
    error TRANSFER_FAIL();
    /// @notice Thrown if category stats or user metrics overflow
    error TXN_OVERFLOW();
    /// @notice Thrown when the emergency rescue token address is the zero address
    error EMG_INVALID_TOKEN();
    /// @notice Thrown when the recovery destination is not the emergency rescue vault
    error EMG_INVALID_RECIP();
    /// @notice Thrown when the contract has insufficient ERC20 token balance for recovery
    error EMG_INSUF_BAL();
    /// @notice Thrown when the low-level ERC20 recovery transfer fails
    error EMG_TRANSFER_FAIL();
    /// @notice Thrown when calling BNB rescue before the 30-day lock period from launch
    error EMG_WAIT_30D();
    /// @notice Thrown when contract BNB balance is less than requested withdrawal amount
    error EMG_INSUF_BAL_BNB();
    /// @notice Thrown when low-level BNB rescue transfer fails
    error EMG_BNB_FAIL();

    // ===================================================
    // MODIFIERS
    // ===================================================

    /// @dev Restricts access to governance role holders or accounts holding the specified role.
    ///      Queries roles dynamically from the main NTE contract to maintain a single source of truth.
    modifier onlyRoleOrGov(bytes32 role) {
        if (!nte.hasRole(role, msg.sender) && !nte.hasRole(GOVERNANCE_ROLE, msg.sender)) revert AUTH_INVALID();
        _;
    }

    /// @dev Restricts access to governance role holders.
    ///      Queries governance permissions dynamically from the main NTE contract.
    modifier onlyGov() {
        if (!nte.hasRole(GOVERNANCE_ROLE, msg.sender)) revert AUTH_INVALID();
        _;
    }

    /// @dev Protects functions from reentrant calls.
    modifier nonReentrant() {
        if (_entered) revert SEC_REENTRY();
        _entered = true;
        _;
        _entered = false;
    }

    // ===================================================
    // CONSTRUCTOR
    // ===================================================

    /**
     * @notice Constructor to initialize the category manager contract.
     * @dev Validates the main NTE token address and stores it as an immutable reference.
     * @param _nte The address of the main Node Meta Energy (NTE) token contract.
     */
    constructor(address _nte) {
        if (_nte == address(0)) revert ADDR_ZERO();
        nte = INTE(_nte);
    }

    /**
     * @notice Fallback receive function to accept native currency (BNB).
     */
    receive() external payable {}

    // ===================================================
    // CRUD & SIGNER MANAGEMENT
    // ===================================================

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
     * @custom:access Restricted to SECURITY_ROLE holders or GOVERNANCE_ROLE holders on NTE
     * @custom:emit CategoryStatusUpdated event
     */
    function setCategoryEnabled(uint8 category, bool enabled) external onlyRoleOrGov(SECURITY_ROLE) {
        if (category >= totalCategories) revert CAT_INVALID();
        categoryEnabled[category] = enabled;
        emit CategoryStatusUpdated(category, enabled);
    }
    
    /**
     * @notice Updates the display name of an existing payment category.
     * @dev Useful for rebranding or fixing typos in category names.
     *      Reverts with CAT_INVALID if category doesn't exist, STR_EMPTY if name is empty,
     *      or STR_TOO_LONG if name exceeds MAX_STRING_LENGTH (256 characters).
     * @param category The category ID to rename (must be less than totalCategories)
     * @param newName The new display name for this category (1-256 characters)
     * @custom:access Restricted to SECURITY_ROLE holders or GOVERNANCE_ROLE holders on NTE
     * @custom:validation Name must be non-empty and within length limits
     * @custom:emit CategoryUpdated event
     */
    function updateCategoryName(uint8 category, string calldata newName) external onlyRoleOrGov(SECURITY_ROLE) {
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
     *      Reverts with STR_EMPTY if name is empty, STR_TOO_LONG if exceeds 256 chars,
     *      or CAT_INVALID if already at maximum category count.
     * @param categoryName The display name for the new category (1-256 characters)
     * @return categoryId The newly assigned category ID (0-254)
     * @custom:access Restricted to SECURITY_ROLE holders or GOVERNANCE_ROLE holders on NTE
     * @custom:effects Increments totalCategories counter and enables new category
     * @custom:emit CategoryAdded event with new ID and name
     */
    function addCategory(string calldata categoryName) external onlyRoleOrGov(SECURITY_ROLE) returns (uint8 categoryId) {
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
     * @custom:access Restricted to SECURITY_ROLE holders or GOVERNANCE_ROLE holders on NTE
     * @custom:security Store private keys in secure infrastructure (HSM/KMS recommended)
     * @custom:emit AuthSignerAdded event
     */
    function addAuthSigner(address authAddress) external onlyRoleOrGov(SECURITY_ROLE) {
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
     * @custom:access Restricted to SECURITY_ROLE holders or GOVERNANCE_ROLE holders on NTE
     * @custom:effect Immediately blocks all new signatures from this address
     * @custom:emit AuthSignerRemoved event
     */
    function removeAuthSigner(address authAddress) external onlyRoleOrGov(SECURITY_ROLE) {
        if (!isAuthSigner[authAddress]) revert AUTH_NOT_SET();
        isAuthSigner[authAddress] = false;
        emit AuthSignerRemoved(authAddress);
    }

    // ===================================================
    // EMERGENCY RECOVERY
    // ===================================================

    /**
     * @notice Emergency function to withdraw stuck ERC20 tokens from this contract.
     * @dev Allows governance to recover standard or non-standard ERC20 tokens sent
     *      accidentally to the category manager contract.
     *      Reverts with EMG_INVALID_TOKEN if token is zero,
     *      EMG_INVALID_RECIP if destination is not the emergency rescue vault of NTE,
     *      EMG_INSUF_BAL if contract balance is less than amount,
     *      or EMG_TRANSFER_FAIL if transfer fails.
     * @param token The address of the ERC20 token to withdraw.
     * @param to The recipient address (must match the emergencyRescueVault of the NTE contract).
     * @param amount The amount of tokens to withdraw.
     * @custom:access Restricted to GOVERNANCE_ROLE holders (via onlyGov modifier).
     * @custom:safety Low-level call handles standard and non-standard ERC20 tokens.
     * @custom:emit EmergencyTokenWithdraw event
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyGov nonReentrant {
        if (token == address(0)) revert EMG_INVALID_TOKEN();
        if (to != nte.emergencyRescueVault()) revert EMG_INVALID_RECIP();
        
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
     * @dev Allows governance to recover BNB that was sent to the contract.
     *      Safety restriction requires waiting 30 days after NTE's launch to prevent abuse.
     *      Reverts with EMG_WAIT_30D if called before 30-day period,
     *      EMG_INVALID_RECIP if recipient is not the emergency rescue vault of NTE,
     *      EMG_INSUF_BAL_BNB if contract has insufficient BNB balance,
     *      or EMG_BNB_FAIL if the BNB transfer fails.
     * @param to The recipient address (must match the emergencyRescueVault of the NTE contract).
     * @param amount The amount of BNB to withdraw in wei.
     * @custom:access Restricted to GOVERNANCE_ROLE holders (via onlyGov modifier).
     * @custom:security 30-day lock period from launch time prevents immediate withdrawal.
     * @custom:emit EmergencyBNBWithdraw event
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyGov nonReentrant {
        if (block.timestamp <= nte.launchTime() + OWNERSHIP_LOCK_PERIOD) revert EMG_WAIT_30D();
        if (to != nte.emergencyRescueVault()) revert EMG_INVALID_RECIP();
        if (amount > address(this).balance) revert EMG_INSUF_BAL_BNB();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert EMG_BNB_FAIL();
        
        emit EmergencyBNBWithdraw(to, amount);
    }

    // ===================================================
    // SIGNATURE RECOVERY & TRANSFERS
    // ===================================================

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

        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);

        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        address recovered = ecrecover(_ethSignedMessageHash, v, r, s);
        if (recovered == address(0)) return address(0);
        
        return recovered;
    }

    /**
     * @dev Internal execution routine to validate signatures, verify nonces, update metrics,
     *      and execute the underlying token transfer from the sender to the recipient.
     * @param from The token owner authorizing the transfer.
     * @param to The recipient address.
     * @param amount The number of NTE tokens to move (base units, 18 decimals).
     * @param category The category ID under which this transaction is classified.
     * @param signature The 65-byte ECDSA off-chain signature by an authorized signer.
     * @param nonce The sequential nonce of the user to prevent transaction replay.
     * @param deadline The unix timestamp expiration after which the signature is void.
     * @param txReference An external transaction reference string (max 256 characters).
     * @param memo An optional memo or note string (max 256 characters).
     * @return success True if the transfer, validations, and statistics logging were successful.
     */
    function _transactionFrom(
        address from,
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) internal returns (bool) {
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
                block.chainid
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

        bool success = nte.transferFrom(from, to, amount);
        if (!success) revert TRANSFER_FAIL();

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

    // ===================================================
    // 50 SEMANTIC CATEGORY ALIASES
    // ===================================================

    function Transaction(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Payment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Reward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Bonus(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Payout(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Deposit(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Withdrawal(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Purchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Refund(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Fee(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Subscription(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Sell(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Gift(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Others(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Airdrop(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Mint(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Royalty(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Incentive(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Penalty(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Cashback(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Swap(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Bridge(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Escrow(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Loan(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Repayment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Rent(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Claim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function LevelUpReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function MoveToEarnReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function TournamentPrize(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function GovernanceVotingFee(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function CardPayment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Salary(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function StakingReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function FarmingReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function LotteryPrize(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Charity(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Donation(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function Tip(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function PartnerPayment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function ReferralBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function CoreNodePurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function EliteNodePurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function CoreNodeBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function EliteNodeBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function StakingPurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function StakingBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function MetaPulsePurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function MetaPulseBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function DBEPurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    function DBEBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        uint256 deadline,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return _transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }
}
