// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20MinimalMigration {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Migrates holders 1:1 from an old token to NTE based on their old balance.
/// Fund this contract with NTE, then call migrateFromOldBalances or let users claim().
/// Zero-balance holders are skipped (not marked migrated) so they can claim later.
contract NTEMigrationHelper {
    address public immutable oldToken;
    address public immutable newToken;
    address public owner;
    address public pendingOwner;
    uint256 public immutable launchTime;

    uint256 public constant MAX_BATCH_SIZE = 100;
    uint256 public constant CLOSE_GRACE_PERIOD = 7 days;
    uint256 private constant OWNERSHIP_LOCK_PERIOD = 30 days;

    mapping(address => bool) public migrated;
    bool public migrationClosed;
    bool public migrationClosedPermanently;
    uint256 public migrationCloseRequestTime; // 0 if no request pending
    uint256 public claimDeadline;             // 0 means no deadline
    bool public batchInProgress;

    bool private _entered;

    event MigrationExecuted(address indexed holder, uint256 amount);
    event MigrationFailed(address indexed holder, uint256 amount, string reason);
    event MigrationSkipped(address indexed holder, string reason);
    event MigrationClosed(uint256 timestamp, bool permanent);
    event MigrationReopened(uint256 timestamp);
    event MigrationCloseRequested(uint256 requestTime, uint256 effectiveTime);
    event MigrationCloseCancelled(uint256 timestamp);
    event ClaimDeadlineSet(uint256 deadline);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    event EmergencyBNBWithdraw(address indexed to, uint256 amount);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    event NativeRescued(address indexed to, uint256 amount);
    event MigrationInitialized(address indexed oldToken, address indexed newToken, address indexed owner);
    event BatchProcessed(bytes32 indexed operation, uint256 totalInput, uint256 successful, uint256 failed, uint256 skipped);

    bytes32 private constant OP_MIGRATE = "MIGRATE_FROM_OLD_BALANCES";
    bytes32 private constant OP_CLAIM_FOR = "CLAIM_FOR";

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    modifier nonReentrant() {
        require(!_entered, "REENTRANT_CALL");
        _entered = true;
        _;
        _entered = false;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "ONLY_SELF");
        _;
    }

    /**
     * @notice Deploys a new migration helper to facilitate 1:1 token migration.
     * @dev Validates both token addresses are contracts with correct ERC20 interface.
     *      Deployer becomes the initial owner responsible for funding this contract with NTE
     *      and triggering batch migrations. Users can also self-claim via claim().
     * @param _oldToken Address of the legacy token being migrated from.
     * @param _newToken Address of the new NTE token being migrated to.
     * @custom:example constructor(0xOLD...token, 0xNEW...NTE)
     * @custom:security Validates tokens are non-zero, different, are contracts, and implement balanceOf.
     * @custom:reverts "OLD_ZERO" if old token is zero address.
     * @custom:reverts "NEW_ZERO" if new token is zero address.
     * @custom:reverts "SAME_TOKEN" if both addresses are identical.
     * @custom:reverts "OLD_NOT_CONTRACT" if old token is not a contract.
     * @custom:reverts "NEW_NOT_CONTRACT" if new token is not a contract.
     * @custom:reverts "OLD_INVALID_INTERFACE" if old token doesn't implement balanceOf.
     * @custom:reverts "NEW_INVALID_INTERFACE" if new token doesn't implement balanceOf.
     * @custom:usecase Deploy migration helper, fund with NTE, then run migrateFromOldBalances for holders.
     */
    constructor(address _oldToken, address _newToken) {
        require(_oldToken != address(0), "OLD_ZERO");
        require(_newToken != address(0), "NEW_ZERO");
        require(_oldToken != _newToken, "SAME_TOKEN");
        
        require(_isContract(_oldToken), "OLD_NOT_CONTRACT");
        require(_isContract(_newToken), "NEW_NOT_CONTRACT");
        
        try IERC20MinimalMigration(_oldToken).balanceOf(address(this)) returns (uint256) {
        } catch {
            revert("OLD_INVALID_INTERFACE");
        }
        
        try IERC20MinimalMigration(_newToken).balanceOf(address(this)) returns (uint256) {
        } catch {
            revert("NEW_INVALID_INTERFACE");
        }
        
        oldToken = _oldToken;
        newToken = _newToken;
        owner = msg.sender;
        launchTime = block.timestamp;
        
        emit MigrationInitialized(_oldToken, _newToken, msg.sender);
    }
    
    /**
     * @notice Initiates a two-step ownership transfer.
     * @dev New owner must call acceptOwnership() to complete the transfer.
     *      The current owner can cancel via cancelOwnershipTransfer() before acceptance.
     * @param newOwner The address of the new owner.
     * @custom:example transferOwnership(0x456...newOwner)
     * @custom:security Prevents transfers to zero address or current owner.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "ZERO_ADDRESS" if newOwner is the zero address.
     * @custom:reverts "ALREADY_OWNER" if newOwner is already the current owner.
     * @custom:usecase Transfer migration helper ownership to new admin or multisig.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_ADDRESS");
        require(newOwner != owner, "ALREADY_OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /**
     * @notice Accepts ownership transfer and completes the two-step change.
     * @dev Only the pending owner can complete the transfer.
     * @custom:example acceptOwnership() // called by pending owner
     * @custom:security Only callable by address set in transferOwnership().
     * @custom:reverts "NOT_PENDING_OWNER" if caller is not the pending owner.
     * @custom:usecase Complete ownership transfer after previous owner initiated it.
     */
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "NOT_PENDING_OWNER");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    /**
     * @notice Cancels a pending ownership transfer before acceptance.
     * @dev Resets pendingOwner to zero, allowing owner to keep ownership or transfer elsewhere.
     * @custom:example cancelOwnershipTransfer() // reverts pending  transfer
     * @custom:security Only current owner can cancel.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "NO_PENDING_TRANSFER" if there is no pending transfer to cancel.
     * @custom:usecase Cancel mistaken ownership transfer or revoke access before acceptance.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        require(pendingOwner != address(0), "NO_PENDING_TRANSFER");
        pendingOwner = address(0);
        emit OwnershipTransferStarted(owner, address(0));
    }

    /**
     * @notice Renounces ownership permanently after the 30-day lock period.
     * @dev Sets owner to zero address, making owner-only functions permanently inaccessible.
     *      Users can still claim() their tokens; only admin functions become disabled.
     * @custom:example renounceOwnership() // 31+ days after deployment
     * @custom:security Requires 30 days since launch to prevent accidental early renunciation.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "OWNER_LOCKED" if called before launchTime + 30 days.
     * @custom:usecase Decentralize migration after all planned batch migrations complete.
     */
    function renounceOwnership() external onlyOwner {
        require(block.timestamp > launchTime + OWNERSHIP_LOCK_PERIOD, "OWNER_LOCKED");
        address oldOwner = owner;
        owner = address(0);
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, address(0));
    }

    /**
     * @notice Returns the NTE balance held by this contract available for migration.
     * @dev This balance must be sufficient to cover all pending migrations.
     *      Owner should fund this contract with enough NTE before running batch migrations.
     * @return The amount of NTE tokens held by this contract.
     * @custom:example getContractBalance() => 1000000e18
     * @custom:usecase Check available NTE balance before batch migration to ensure sufficient funds.
     */
    function getContractBalance() external view returns (uint256) {
        return IERC20MinimalMigration(newToken).balanceOf(address(this));
    }

    /**
     * @notice Returns how many NTE tokens the account can claim from this migration.
     * @dev Checks old token balance and migration status. Returns 0 if already migrated or
     *      if old balance read fails.
     * @param account The address to check claimable amount for.
     * @return The amount of NTE claimable (equals old token balance if not migrated, else 0).
     * @custom:example getClaimableAmount(0x123...user) => 500e18
     * @custom:example getClaimableAmount(migratedUser) => 0
     * @custom:security Returns 0 on external call failures rather than reverting.
     * @custom:reverts "ZERO_ADDRESS" if account is the zero address.
     * @custom:usecase Check user's claimable amount before calling claim().
     */
    function getClaimableAmount(address account) public view returns (uint256) {
        require(account != address(0), "ZERO_ADDRESS");
        
        if (migrated[account]) {
            return 0;
        }
        
        try IERC20MinimalMigration(oldToken).balanceOf(account) returns (uint256 balance) {
            return balance;
        } catch {
            return 0;
        }
    }
    
    /**
     * @notice Checks whether the contract holds enough NTE to cover all unmigrated holders.
     * @dev Sums old token balances for all provided holders (excluding already-migrated and duplicates)
     *      and compares against current NTE balance in this contract.
     * @param holders Array of holder addresses to check (max 100).
     * @return hasSufficient True if contract has enough NTE for all holders.
     * @return required Total NTE needed for the provided holders.
     * @return available Current NTE balance in this contract.
     * @custom:example checkSufficientBalance([0x1, 0x2, 0x3]) => (true, 10000e18, 15000e18)
     * @custom:security Ignores duplicate addresses and already-migrated accounts.
     * @custom:reverts "BATCH_TOO_LARGE" if holders array exceeds MAX_BATCH_SIZE (100).
     * @custom:usecase Verify sufficient funding before calling migrateFromOldBalances().
     */
    function checkSufficientBalance(address[] calldata holders) external view returns (bool hasSufficient, uint256 required, uint256 available) {
        require(holders.length <= MAX_BATCH_SIZE, "BATCH_TOO_LARGE");
        
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);
        uint256 length = holders.length;
        
        for (uint256 i = 0; i < length;) {
            address holder = holders[i];
            if (
                holder != address(0) &&
                !migrated[holder] &&
                !_hasPriorOccurrence(holders, i, holder)
            ) {
                try oldT.balanceOf(holder) returns (uint256 balance) {
                    required += balance;
                } catch {}
            }
            unchecked { ++i; }
        }
        
        available = IERC20MinimalMigration(newToken).balanceOf(address(this));
        hasSufficient = available >= required;
    }

    /**
     * @notice Calculates total NTE needed to migrate the given holder list.
     * @dev Excludes already-migrated addresses and duplicate entries from calculation.
     *      Silently ignores balance read failures (returns 0 for those holders).
     * @param holders Array of holder addresses to calculate total for (max 100).
     * @return totalAmount Sum of old token balances for all unmigrated, unique holders.
     * @custom:example getTotalAmountFromOldBalances([0x1, 0x2]) => 5000e18
     * @custom:security Skips zero addresses, migrated accounts, and duplicates automatically.
     * @custom:reverts "BATCH_TOO_LARGE" if holders array exceeds MAX_BATCH_SIZE (100).
     * @custom:usecase Calculate required NTE before funding the migration contract.
     */
    function getTotalAmountFromOldBalances(address[] calldata holders) external view returns (uint256 totalAmount) {
        require(holders.length <= MAX_BATCH_SIZE, "BATCH_TOO_LARGE");
        
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);

        uint256 length = holders.length;
        for (uint256 i = 0; i < length;) {
            address holder = holders[i];
            if (holder == address(0)) {
                unchecked { ++i; }
                continue;
            }
            if (migrated[holder]) {
                unchecked { ++i; }
                continue;
            }
            if (_hasPriorOccurrence(holders, i, holder)) {
                unchecked { ++i; }
                continue;
            }

            try oldT.balanceOf(holder) returns (uint256 balance) {
                totalAmount += balance;
            } catch {}
            unchecked { ++i; }
        }
    }

    /**
     * @notice Owner-triggered batch migration for multiple holders.
     * @dev Pre-fund this contract with NTE first. Reads all old balances, validates sufficient funds,
     *      then executes transfers. Failures on individual addresses emit events but don't revert the batch.
     *      Zero-balance holders are skipped and not marked as migrated so they can claim later.
     * @param holders Array of holder addresses to migrate (max 100).
     * @custom:example migrateFromOldBalances([0x1, 0x2, 0x3])
     * @custom:security Validates sufficient funds before any state changes; handles failures gracefully.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "REENTRANT_CALL" on reentrant attempts.
     * @custom:reverts "MIGRATION_CLOSED" if migration has been closed.
     * @custom:reverts "BATCH_IN_PROGRESS" if another batch is currently processing.
     * @custom:reverts "BATCH_TOO_LARGE" if holders array exceeds 100.
     * @custom:reverts "CLAIM_DEADLINE_PASSED" if claim deadline has passed.
     * @custom:reverts "INSUFFICIENT_FUNDS" if contract doesn't hold enough NTE.
     * @custom:usecase Batch migrate holders efficiently; fund contract first.
     */
    function migrateFromOldBalances(address[] calldata holders) external onlyOwner nonReentrant {
        require(!migrationClosed, "MIGRATION_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        require(holders.length <= MAX_BATCH_SIZE, "BATCH_TOO_LARGE");
        
        if (claimDeadline != 0) {
            require(block.timestamp <= claimDeadline, "CLAIM_DEADLINE_PASSED");
        }
        
        batchInProgress = true;
        
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);
        IERC20MinimalMigration newT = IERC20MinimalMigration(newToken);
        uint256 length = holders.length;
        
        // read all balances first so we can verify INSUFFICIENT_FUNDS before touching state
        uint256[] memory amounts = new uint256[](length);
        bool[] memory balanceReadFailed = new bool[](length);
        bool[] memory duplicateAccount = new bool[](length);
        uint256 requiredBalance = 0;
        uint256 successCount = 0;
        uint256 failedCount = 0;
        uint256 skippedCount = 0;
        
        for (uint256 i = 0; i < length;) {
            address holder = holders[i];
            if (holder == address(0) || migrated[holder]) {
                unchecked { ++i; }
                continue;
            }
            if (_hasPriorOccurrence(holders, i, holder)) {
                duplicateAccount[i] = true;
                unchecked { ++i; }
                continue;
            }
            if (
                holder != address(0) &&
                !migrated[holder] &&
                !duplicateAccount[i]
            ) {
                try oldT.balanceOf(holder) returns (uint256 balance) {
                    amounts[i] = balance;
                    requiredBalance += balance;
                } catch {
                    amounts[i] = 0;
                    balanceReadFailed[i] = true;
                }
            }
            unchecked { ++i; }
        }
        
        uint256 availableBalance = newT.balanceOf(address(this));
        require(availableBalance >= requiredBalance, "INSUFFICIENT_FUNDS");

        for (uint256 i = 0; i < length;) {
            address holder = holders[i];
            uint256 amount = amounts[i];
            
            if (holder == address(0)) {
                skippedCount++;
                unchecked { ++i; }
                continue;
            }
            if (migrated[holder]) {
                skippedCount++;
                unchecked { ++i; }
                continue;
            }
            if (duplicateAccount[i]) {
                emit MigrationSkipped(holder, "DUPLICATE_ACCOUNT");
                skippedCount++;
                unchecked { ++i; }
                continue;
            }

            if (amount == 0) {
                // skip but don't mark migrated — they can still claim if they acquire old tokens
                if (balanceReadFailed[i]) {
                    emit MigrationSkipped(holder, "BALANCE_READ_FAILED");
                } else {
                    emit MigrationSkipped(holder, "ZERO_BALANCE");
                }
                skippedCount++;
                unchecked { ++i; }
                continue;
            }

            try this._transferAndValidate(holder, amount) returns (bool success) {
                if (!success) {
                    emit MigrationFailed(holder, amount, "TRANSFER_VALIDATION_FAILED");
                    failedCount++;
                    unchecked { ++i; }
                    continue;
                }
                migrated[holder] = true;
                emit MigrationExecuted(holder, amount);
                successCount++;
            } catch (bytes memory reason) {
                string memory revertReason = _extractRevertReason(reason, "TRANSFER_REVERTED");
                emit MigrationFailed(holder, amount, revertReason);
                failedCount++;
            }
            unchecked { ++i; }
        }
        
        batchInProgress = false;
        emit BatchProcessed(OP_MIGRATE, length, successCount, failedCount, skippedCount);
    }

    /**
     * @notice Allows users to claim their NTE based on current old-token balance.
     * @dev Reads caller's old token balance, marks them as migrated, and transfers matching NTE.
     *      Zero-balance holders will revert with "NO_BALANCE".
     * @custom:example claim() // user claims their migration
     * @custom:security Non-reentrant, validates balance exists, handles transfer failures gracefully.
     * @custom:reverts "REENTRANT_CALL" on reentrant attempts.
     * @custom:reverts "MIGRATION_CLOSED" if migration has been closed.
     * @custom:reverts "BATCH_IN_PROGRESS" if a batch operation is currently processing.
     * @custom:reverts "CLAIM_DEADLINE_PASSED" if claim deadline has passed.
     * @custom:reverts "ALREADY_MIGRATED" if caller has already migrated.
     * @custom:reverts "BALANCE_READ_FAILED" if old token balance read fails.
     * @custom:reverts "NO_BALANCE" if caller has zero old token balance.
     * @custom:usecase Users self-claim their NTE migration after helper is funded.
     */
    function claim() external nonReentrant {
        require(!migrationClosed, "MIGRATION_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        
        if (claimDeadline != 0) {
            require(block.timestamp <= claimDeadline, "CLAIM_DEADLINE_PASSED");
        }
        
        address account = msg.sender;
        require(!migrated[account], "ALREADY_MIGRATED");

        uint256 amount;
        try IERC20MinimalMigration(oldToken).balanceOf(account) returns (uint256 balance) {
            amount = balance;
        } catch {
            revert("BALANCE_CHECK_FAILED");
        }
        
        require(amount > 0, "NO_BALANCE");

        try this._transferAndValidate(account, amount) returns (bool success) {
            require(success, "TRANSFER_VALIDATION_FAILED");
            migrated[account] = true;
            emit MigrationExecuted(account, amount);
        } catch (bytes memory reason) {
            string memory revertReason = _extractRevertReason(reason, "TRANSFER_REVERTED");
            revert(revertReason);
        }
    }

    /**
     * @notice Allows owner to claim NTE migration on behalf of users who cannot do it themselves.
     * @dev Batch processes multiple accounts; failures emit events without reverting the batch.
     *      Pre-reads all balances to validate sufficient contract funding before processing.
     *      Skips zero addresses, already-migrated accounts, duplicates, and zero-balance accounts.
     * @param accounts Array of user addresses to claim for (max MAX_BATCH_SIZE).
     * @custom:example claimFor([0x123..., 0x456...]) // owner helps users migrate
     * @custom:security Non-reentrant; validates closure status, deadline, batch size, and funding.
     * @custom:reverts "REENTRANT_CALL" on reentrant attempts.
     * @custom:reverts "MIGRATION_CLOSED" if migration has been closed.
     * @custom:reverts "BATCH_IN_PROGRESS" if another batch is processing.
     * @custom:reverts "BATCH_TOO_LARGE" if accounts array exceeds MAX_BATCH_SIZE.
     * @custom:reverts "CLAIM_DEADLINE_PASSED" if deadline has elapsed.
     * @custom:reverts "INSUFFICIENT_FUNDS" if contract lacks sufficient NTE for all claims.
     * @custom:usecase Owner helps users without technical skills or gas to claim their migration.
     */
    function claimFor(address[] calldata accounts) external onlyOwner nonReentrant {
        require(!migrationClosed, "MIGRATION_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        require(accounts.length <= MAX_BATCH_SIZE, "BATCH_TOO_LARGE");
        
        if (claimDeadline != 0) {
            require(block.timestamp <= claimDeadline, "CLAIM_DEADLINE_PASSED");
        }
        
        batchInProgress = true;
        
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);
        IERC20MinimalMigration newT = IERC20MinimalMigration(newToken);
        uint256 length = accounts.length;
        
        // read all balances first so we can verify INSUFFICIENT_FUNDS before touching state
        uint256[] memory amounts = new uint256[](length);
        bool[] memory balanceReadFailed = new bool[](length);
        bool[] memory duplicateAccount = new bool[](length);
        uint256 requiredBalance = 0;
        uint256 successCount = 0;
        uint256 failedCount = 0;
        uint256 skippedCount = 0;
        
        for (uint256 i = 0; i < length;) {
            address account = accounts[i];
            if (account == address(0) || migrated[account]) {
                unchecked { ++i; }
                continue;
            }
            if (_hasPriorOccurrence(accounts, i, account)) {
                duplicateAccount[i] = true;
                unchecked { ++i; }
                continue;
            }
            if (
                account != address(0) &&
                !migrated[account] &&
                !duplicateAccount[i]
            ) {
                try oldT.balanceOf(account) returns (uint256 balance) {
                    amounts[i] = balance;
                    requiredBalance += balance;
                } catch {
                    amounts[i] = 0;
                    balanceReadFailed[i] = true;
                }
            }
            unchecked { ++i; }
        }
        
        uint256 availableBalance = newT.balanceOf(address(this));
        require(availableBalance >= requiredBalance, "INSUFFICIENT_FUNDS");

        for (uint256 i = 0; i < length;) {
            address account = accounts[i];
            uint256 amount = amounts[i];
            
            if (account == address(0)) {
                skippedCount++;
                unchecked { ++i; }
                continue;
            }
            if (migrated[account]) {
                skippedCount++;
                unchecked { ++i; }
                continue;
            }
            if (duplicateAccount[i]) {
                emit MigrationSkipped(account, "DUPLICATE_ACCOUNT");
                skippedCount++;
                unchecked { ++i; }
                continue;
            }
            
            if (amount == 0) {
                // skip but don't mark migrated — they can still claim if they acquire old tokens
                if (balanceReadFailed[i]) {
                    emit MigrationSkipped(account, "BALANCE_READ_FAILED");
                } else {
                    emit MigrationSkipped(account, "ZERO_BALANCE");
                }
                skippedCount++;
                unchecked { ++i; }
                continue;
            }
            
            try this._transferAndValidate(account, amount) returns (bool success) {
                if (!success) {
                    emit MigrationFailed(account, amount, "TRANSFER_VALIDATION_FAILED");
                    failedCount++;
                    unchecked { ++i; }
                    continue;
                }
                migrated[account] = true;
                emit MigrationExecuted(account, amount);
                successCount++;
            } catch (bytes memory reason) {
                string memory revertReason = _extractRevertReason(reason, "TRANSFER_REVERTED");
                emit MigrationFailed(account, amount, revertReason);
                failedCount++;
            }
            unchecked { ++i; }
        }
        
        batchInProgress = false;
        emit BatchProcessed(OP_CLAIM_FOR, length, successCount, failedCount, skippedCount);
    }

    /**
     * @notice Sets a unix timestamp after which all claims will be rejected.
     * @dev Pass 0 to remove the deadline and allow indefinite claiming.
     *      Deadline must be in the future if non-zero; emits ClaimDeadlineSet event.
     * @param deadline Unix timestamp (seconds since epoch), or 0 to remove deadline.
     * @custom:example setClaimDeadline(1735689600) // set deadline to Jan 1, 2025
     * @custom:example setClaimDeadline(0) // remove deadline, allow claims indefinitely
     * @custom:security Only owner; validates deadline is future timestamp or zero.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "INVALID_DEADLINE" if deadline is non-zero but in the past.
     * @custom:usecase Set time limit for migration window or extend deadline for late claimers.
     */
    function setClaimDeadline(uint256 deadline) external onlyOwner {
        require(deadline == 0 || deadline > block.timestamp, "INVALID_DEADLINE");
        claimDeadline = deadline;
        emit ClaimDeadlineSet(deadline);
    }
    
    /**
     * @notice Pauses migration temporarily; can be reopened unless permanently closed.
     * @dev Sets migrationClosed to true. Does not affect permanent closure requests.
     *      Migration can still be permanently closed while temporarily closed.
     * @custom:example closeMigration() // pause for maintenance
     * @custom:security Only owner; validates not permanently closed, no batch in progress.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "PERMANENTLY_CLOSED" if migration is permanently closed.
     * @custom:reverts "BATCH_IN_PROGRESS" if batch operation is processing.
     * @custom:usecase Temporarily halt migration during contract issues or maintenance.
     */
    function closeMigration() external onlyOwner {
        require(!migrationClosedPermanently, "PERMANENTLY_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        migrationClosed = true;
        emit MigrationClosed(block.timestamp, false);
    }
    
    /**
     * @notice Reopens a temporarily closed migration.
     * @dev Sets migrationClosed to false and cancels any pending permanent closure request.
     *      Cannot reopen if migration is permanently closed.
     * @custom:example reopenMigration() // resume after maintenance
     * @custom:security Only owner; validates migration is closed and not permanently closed.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "NOT_CLOSED" if migration is not currently closed.
     * @custom:reverts "PERMANENTLY_CLOSED" if migration is permanently closed.
     * @custom:usecase Resume migration after resolving temporary issues.
     */
    function reopenMigration() external onlyOwner {
        require(migrationClosed, "NOT_CLOSED");
        require(!migrationClosedPermanently, "PERMANENTLY_CLOSED");
        migrationClosed = false;
        // also cancel any pending permanent closure
        if (migrationCloseRequestTime != 0) {
            migrationCloseRequestTime = 0;
            emit MigrationCloseCancelled(block.timestamp);
        }
        emit MigrationReopened(block.timestamp);
    }
    
    /**
     * @notice Schedules permanent migration closure; takes effect after CLOSE_GRACE_PERIOD (7 days).
     * @dev Records request timestamp; gives users 7-day window to claim before finalization.
     *      Can be canceled before executePermanentClosure() is called.
     * @custom:example requestPermanentClosure() // start 7-day countdown
     * @custom:security Only owner; validates not already permanently closed, no pending request, no batch.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "ALREADY_PERMANENTLY_CLOSED" if already permanently closed.
     * @custom:reverts "BATCH_IN_PROGRESS" if batch operation is processing.
     * @custom:reverts "CLOSURE_ALREADY_REQUESTED" if another closure request is pending.
     * @custom:usecase Initiate migration wind-down with grace period for late claimers.
     */
    function requestPermanentClosure() external onlyOwner {
        require(!migrationClosedPermanently, "ALREADY_PERMANENTLY_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        require(migrationCloseRequestTime == 0, "CLOSURE_ALREADY_REQUESTED");
        
        migrationCloseRequestTime = block.timestamp;
        uint256 effectiveTime = block.timestamp + CLOSE_GRACE_PERIOD;
        
        emit MigrationCloseRequested(block.timestamp, effectiveTime);
    }
    
    /**
     * @notice Cancels a pending permanent closure request before grace period ends.
     * @dev Resets migrationCloseRequestTime to 0, allowing indefinite migration or new request.
     * @custom:example cancelPermanentClosure() // abort closure decision
     * @custom:security Only owner; validates closure request exists and not yet executed.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "NO_CLOSURE_REQUESTED" if no closure request is pending.
     * @custom:reverts "ALREADY_CLOSED" if migration is permanently closed.
     * @custom:usecase Cancel permanent closure if migration needs to continue longer.
     */
    function cancelPermanentClosure() external onlyOwner {
        require(migrationCloseRequestTime != 0, "NO_CLOSURE_REQUESTED");
        require(!migrationClosedPermanently, "ALREADY_CLOSED");
        
        migrationCloseRequestTime = 0;
        emit MigrationCloseCancelled(block.timestamp);
    }
    
    /**
     * @notice Finalizes permanent migration closure once the 7-day grace period has elapsed.
     * @dev Sets both migrationClosed and migrationClosedPermanently to true.
     *      Once executed, migration can never be reopened. Irreversible action.
     * @custom:example executePermanentClosure() // finalize after 7+ days
     * @custom:security Only owner; validates request exists, grace period elapsed, not already closed.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "NO_CLOSURE_REQUESTED" if no closure request exists.
     * @custom:reverts "GRACE_PERIOD_NOT_ELAPSED" if called before grace period ends.
     * @custom:reverts "ALREADY_CLOSED" if already permanently closed.
     * @custom:usecase Complete migration shutdown after grace period; allows token recovery.
     */
    function executePermanentClosure() external onlyOwner {
        require(migrationCloseRequestTime != 0, "NO_CLOSURE_REQUESTED");
        require(block.timestamp >= migrationCloseRequestTime + CLOSE_GRACE_PERIOD, "GRACE_PERIOD_NOT_ELAPSED");
        require(!migrationClosedPermanently, "ALREADY_CLOSED");
        
        migrationClosed = true;
        migrationClosedPermanently = true;
        emit MigrationClosed(block.timestamp, true);
    }

    /**
     * @notice Withdraws any ERC20 token from this contract, including leftover NTE.
     * @dev Uses low-level call to handle non-standard ERC20 implementations.
     *      Can withdraw remaining NTE after migration completes. Emits dual events.
     * @param token The ERC20 token address to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     * @param amount The number of tokens to withdraw.
     * @custom:example emergencyWithdrawToken(0xNTE..., owner, 1000e18)
     * @custom:security Only owner, non-reentrant; validates addresses and balance.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "REENTRANT_CALL" on reentrant attempts.
     * @custom:reverts "INVALID_TOKEN" if token is zero address.
     * @custom:reverts "ZERO_RECIPIENT" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_TOKEN_BALANCE" if contract lacks sufficient balance.
     * @custom:reverts "TOKEN_TRANSFER_FAIL" if transfer fails.
     * @custom:usecase Recover leftover NTE or accidentally sent tokens after migration ends.
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        _withdrawToken(token, to, amount);
    }

    /**
     * @notice Legacy alias for emergencyWithdrawToken().
     * @dev Maintains backward compatibility with earlier contract versions.
     *      Identical functionality to emergencyWithdrawToken().
     * @param token The ERC20 token address to rescue.
     * @param to The recipient address for the rescued tokens.
     * @param amount The number of tokens to rescue.
     * @custom:example rescueToken(0xNTE..., owner, 1000e18)
     * @custom:security Identical security constraints as emergencyWithdrawToken().
     * @custom:usecase Use emergencyWithdrawToken() for clarity; this is legacy support.
     */
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        _withdrawToken(token, to, amount);
    }

    /**
     * @notice Recovers native BNB/ETH accidentally sent to this migration contract.
     * @dev Subject to 30-day ownership lock period from deployment.
     *      Uses low-level call for native coin transfer with success validation.
     * @param to The recipient address for the withdrawn BNB/ETH.
     * @param amount The amount of native coin (in wei) to withdraw.
     * @custom:example emergencyWithdrawBNB(payable(owner), 1 ether)
     * @custom:security Only owner, non-reentrant; 30-day lock prevents immediate drainage.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "REENTRANT_CALL" on reentrant attempts.
     * @custom:reverts "EMG_WAIT_30D" if called before launchTime + 30 days.
     * @custom:reverts "INVALID_RECIPIENT" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_NATIVE" if contract lacks sufficient balance.
     * @custom:reverts "NATIVE_RESCUE_FAILED" if transfer call fails.
     * @custom:usecase Recover BNB/ETH sent to contract by mistake after 30-day safety period.
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        _withdrawNative(to, amount);
    }

    /**
     * @notice Legacy alias for emergencyWithdrawBNB().
     * @dev Maintains backward compatibility with earlier contract versions.
     *      Identical functionality to emergencyWithdrawBNB().
     * @param to The recipient address for the rescued native coin.
     * @param amount The amount of native coin (in wei) to rescue.
     * @custom:example rescueNative(payable(owner), 1 ether)
     * @custom:security Identical security constraints as emergencyWithdrawBNB().
     * @custom:usecase Use emergencyWithdrawBNB() for clarity; this is legacy support.
     */
    function rescueNative(address payable to, uint256 amount) external onlyOwner nonReentrant {
        _withdrawNative(to, amount);
    }
    /**
     * @dev Checks if an address contains deployed contract code.
     * @param account The address to check for contract code.
     * @return bool True if address has contract bytecode, false otherwise.
     * @custom:security Uses inline assembly extcodesize; EOAs return size 0.
     * @custom:usecase Validates addresses are not externally-owned accounts (EOAs).
     */
    function _isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Internal handler for ERC20 token withdrawals with non-standard token support.
     * @param token The ERC20 token address to withdraw.
     * @param to The recipient address for withdrawn tokens.
     * @param amount The number of tokens to transfer.
     * @custom:security Low-level call with returndata validation for non-standard tokens.
     * @custom:reverts "INVALID_TOKEN" if token is zero address.
     * @custom:reverts "ZERO_RECIPIENT" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_TOKEN_BALANCE" if contract lacks balance.
     * @custom:reverts "TOKEN_TRANSFER_FAIL" if transfer call fails or returns false.
     * @custom:usecase Supports both standard and non-standard ERC20 implementations.
     */
    function _withdrawToken(address token, address to, uint256 amount) private {
        require(token != address(0), "INVALID_TOKEN");
        require(to != address(0), "ZERO_RECIPIENT");

        uint256 contractBalance = IERC20MinimalMigration(token).balanceOf(address(this));
        require(contractBalance >= amount, "INSUFFICIENT_TOKEN_BALANCE");

        bytes memory payload = abi.encodeWithSelector(IERC20MinimalMigration.transfer.selector, to, amount);
        (bool success, bytes memory returndata) = token.call(payload);
        require(success, "TOKEN_TRANSFER_FAIL");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "TOKEN_TRANSFER_FAIL");
        }

        emit EmergencyTokenWithdraw(token, to, amount);
        emit TokenRescued(token, to, amount);
    }

    /**
     * @dev Internal handler for native BNB/ETH withdrawals with time lock enforcement.
     * @param to The recipient payable address for native coin.
     * @param amount The amount (in wei) to transfer.
     * @custom:security Requires 30-day lock from launch; low-level call with validation.
     * @custom:reverts "EMG_WAIT_30D" if called before launchTime + 30 days.
     * @custom:reverts "INVALID_RECIPIENT" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_NATIVE" if contract lacks balance.
     * @custom:reverts "NATIVE_RESCUE_FAILED" if transfer call fails.
     * @custom:usecase Prevents premature drainage of accidentally sent BNB/ETH.
     */
    function _withdrawNative(address payable to, uint256 amount) private {
        require(block.timestamp > launchTime + OWNERSHIP_LOCK_PERIOD, "EMG_WAIT_30D");
        require(to != address(0), "INVALID_RECIPIENT");
        require(address(this).balance >= amount, "INSUFFICIENT_NATIVE");

        (bool success, ) = to.call{value: amount}("");
        require(success, "NATIVE_RESCUE_FAILED");

        emit EmergencyBNBWithdraw(to, amount);
        emit NativeRescued(to, amount);
    }

    /**
     * @dev External validation for exact token transfer amounts (callable only by self).
     * @param to The recipient address to validate balance change.
     * @param amount The expected exact token amount received.
     * @return bool Always true if validation passes (reverts otherwise).
     * @custom:security Protects against fee-on-transfer/rebasing tokens by validating exact balance change.
     * @custom:reverts "ONLY_SELF" if caller is not this contract.
     * @custom:reverts "TRANSFER_RETURNED_FALSE" if token.transfer() returns false.
     * @custom:reverts "BALANCE_DECREASED" if recipient balance decreased unexpectedly.
     * @custom:reverts "NON_EXACT_TRANSFER" if balance change does not match expected amount.
     * @custom:usecase Ensures migration transfers exact amounts without hidden fees/burns.
     */
    function _transferAndValidate(address to, uint256 amount) external onlySelf returns (bool) {
        IERC20MinimalMigration token = IERC20MinimalMigration(newToken);

        uint256 preBalance = token.balanceOf(to);
        bool success = token.transfer(to, amount);
        require(success, "TRANSFER_RETURNED_FALSE");
        uint256 postBalance = token.balanceOf(to);

        require(postBalance >= preBalance, "BALANCE_DECREASED");
        require(postBalance - preBalance == amount, "NON_EXACT_TRANSFER");
        return true;
    }

    /**
     * @dev Pure function to check for duplicate addresses in accounts array prior to index.
     * @param accounts The array of addresses to search.
     * @param index The current position; searches all positions before this index.
     * @param account The address to search for within [0, index).
     * @return bool True if account appears before index, false otherwise.
     * @custom:security Gas-efficient O(n) duplicate detection for batch processing.
     * @custom:usecase Prevents duplicate claims in migrateFromOldBalances and claimFor arrays.
     */
    function _hasPriorOccurrence(
        address[] calldata accounts,
        uint256 index,
        address account
    ) private pure returns (bool) {
        for (uint256 j = 0; j < index;) {
            if (accounts[j] == account) {
                return true;
            }
            unchecked { ++j; }
        }
        return false;
    }

    /**
     * @dev Parses revert reason from returndata bytes into human-readable string.
     * @param reason The raw bytes returned from a failed call.
     * @param fallbackReason The default message if parsing fails.
     * @return string Decoded error message or fallback reason.
     * @custom:security Handles Error(string), Panic(uint256), and custom errors (selector hex).
     * @custom:usecase Used in claimFor to report user-friendly errors during batch processing.
     */
    function _extractRevertReason(bytes memory reason, string memory fallbackReason) private pure returns (string memory) {
        if (reason.length < 4) {
            return fallbackReason;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 32))
        }

        // Error(string)
        if (selector == 0x08c379a0) {
            // selector + offset + length
            if (reason.length < 68) {
                return fallbackReason;
            }

            uint256 offset;
            uint256 strLen;
            assembly {
                offset := mload(add(reason, 36))
                strLen := mload(add(reason, 68))
            }

            if (offset != 32) {
                return fallbackReason;
            }

            if (strLen > reason.length - 68) {
                return fallbackReason;
            }

            bytes memory strBytes = new bytes(strLen);
            for (uint256 i = 0; i < strLen;) {
                strBytes[i] = reason[68 + i];
                unchecked { ++i; }
            }
            return string(strBytes);
        }

        // Panic(uint256)
        if (selector == 0x4e487b71) {
            if (reason.length < 36) {
                return "PANIC";
            }
            uint256 panicCode;
            assembly {
                panicCode := mload(add(reason, 36))
            }
            return string.concat("PANIC_", _uintToString(panicCode));
        }

        // Most modern Solidity custom errors land here.
        return string.concat("CUSTOM_ERROR_", _selectorToHex(selector));
    }

    /**
     * @dev Converts a bytes4 selector to "0x" prefixed hex string.
     * @param selector The 4-byte function selector or error selector.
     * @return string The hex representation (e.g., "0x08c379a0").
     * @custom:usecase Generates readable custom error identifiers for logging.
     */
    function _selectorToHex(bytes4 selector) private pure returns (string memory) {
        bytes memory out = new bytes(10);
        out[0] = "0";
        out[1] = "x";

        uint32 value = uint32(selector);
        for (uint256 i = 0; i < 4;) {
            uint8 b = uint8(value >> ((3 - i) * 8));
            out[2 + (i * 2)] = _nibbleToHexChar(b >> 4);
            out[3 + (i * 2)] = _nibbleToHexChar(b & 0x0f);
            unchecked { ++i; }
        }

        return string(out);
    }

    /**
     * @dev Converts a single 4-bit nibble (0-15) to its hex character representation.
     * @param nibble The 4-bit value to convert (0-15).
     * @return bytes1 The ASCII hex character ('0'-'9' or 'a'-'f').
     * @custom:usecase Low-level helper for _selectorToHex byte-to-string conversion.
     */
    function _nibbleToHexChar(uint8 nibble) private pure returns (bytes1) {
        if (nibble < 10) {
            return bytes1(nibble + 48);
        }
        return bytes1(nibble + 87);
    }

    /**
     * @dev Converts a uint256 to its decimal string representation.
     * @param value The unsigned integer to convert.
     * @return string The decimal representation (e.g., 42 → "42").
     * @custom:usecase Used in _extractRevertReason for panic code formatting.
     */
    function _uintToString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits = 0;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Fallback function to accept native BNB/ETH transfers.
     * @dev Allows contract to receive native coin without reverting.
     * @custom:usecase Enables accepting BNB/ETH from swaps, refunds, or accidental transfers.
     */
    receive() external payable {}
}
