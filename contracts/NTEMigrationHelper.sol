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

    uint256 public constant MAX_BATCH_SIZE = 100;
    uint256 public constant CLOSE_GRACE_PERIOD = 7 days;

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
        
        emit MigrationInitialized(_oldToken, _newToken, msg.sender);
    }
    
    /// @notice Start a 2-step ownership transfer. New owner must call acceptOwnership().
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_ADDRESS");
        require(newOwner != owner, "ALREADY_OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "NOT_PENDING_OWNER");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    /// @notice NTE balance held by this contract (available for migration).
    function getContractBalance() external view returns (uint256) {
        return IERC20MinimalMigration(newToken).balanceOf(address(this));
    }

    /// @notice How many NTE the account can claim. Returns 0 if already migrated.
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
    
    /// @notice Check whether the contract holds enough NTE to cover all unmigrated holders.
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

    /// @notice Total NTE needed to migrate the given holder list (excludes already-migrated addresses).
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

    /// @notice Owner-triggered batch migration. Pre-fund this contract with NTE first.
    /// Failures on individual addresses are emitted as events and don't revert the batch.
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

    /// @notice Claim your NTE based on your current old-token balance.
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

    /// @notice Claim on behalf of users who can't do it themselves.
    /// Failures on individual addresses are emitted as events and don't revert the batch.
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

    /// @notice Set a unix timestamp after which claims are rejected. Pass 0 to remove the deadline.
    function setClaimDeadline(uint256 deadline) external onlyOwner {
        require(deadline == 0 || deadline > block.timestamp, "INVALID_DEADLINE");
        claimDeadline = deadline;
        emit ClaimDeadlineSet(deadline);
    }
    
    /// @notice Pause migration. Can be reopened unless permanently closed.
    function closeMigration() external onlyOwner {
        require(!migrationClosedPermanently, "PERMANENTLY_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        migrationClosed = true;
        emit MigrationClosed(block.timestamp, false);
    }
    
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
    
    /// @notice Schedule permanent closure. Goes into effect after CLOSE_GRACE_PERIOD (7 days).
    function requestPermanentClosure() external onlyOwner {
        require(!migrationClosedPermanently, "ALREADY_PERMANENTLY_CLOSED");
        require(!batchInProgress, "BATCH_IN_PROGRESS");
        require(migrationCloseRequestTime == 0, "CLOSURE_ALREADY_REQUESTED");
        
        migrationCloseRequestTime = block.timestamp;
        uint256 effectiveTime = block.timestamp + CLOSE_GRACE_PERIOD;
        
        emit MigrationCloseRequested(block.timestamp, effectiveTime);
    }
    
    function cancelPermanentClosure() external onlyOwner {
        require(migrationCloseRequestTime != 0, "NO_CLOSURE_REQUESTED");
        require(!migrationClosedPermanently, "ALREADY_CLOSED");
        
        migrationCloseRequestTime = 0;
        emit MigrationCloseCancelled(block.timestamp);
    }
    
    /// @notice Finalize permanent closure once the grace period has elapsed.
    function executePermanentClosure() external onlyOwner {
        require(migrationCloseRequestTime != 0, "NO_CLOSURE_REQUESTED");
        require(block.timestamp >= migrationCloseRequestTime + CLOSE_GRACE_PERIOD, "GRACE_PERIOD_NOT_ELAPSED");
        require(!migrationClosedPermanently, "ALREADY_CLOSED");
        
        migrationClosed = true;
        migrationClosedPermanently = true;
        emit MigrationClosed(block.timestamp, true);
    }

    /// @notice Pull any ERC20 (including leftover NTE) out of this contract.
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "ZERO_ADDRESS");

        IERC20MinimalMigration erc20 = IERC20MinimalMigration(token);
        require(erc20.transfer(to, amount), "RESCUE_FAILED");
        
        emit TokenRescued(token, to, amount);
    }

    /// @notice Recover native BNB/ETH accidentally sent to this contract.
    function rescueNative(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "ZERO_ADDRESS");
        require(address(this).balance >= amount, "INSUFFICIENT_NATIVE");

        (bool success, ) = to.call{value: amount}("");
        require(success, "NATIVE_RESCUE_FAILED");

        emit NativeRescued(to, amount);
    }
    
    function _isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

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

    function _extractRevertReason(bytes memory reason, string memory fallbackReason) private pure returns (string memory) {
        if (reason.length < 4) {
            return fallbackReason;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 32))
        }

        // must be Error(string) — 0x08c379a0
        if (selector != 0x08c379a0) {
            return fallbackReason;
        }

        // ABI-encoded string: 4-byte selector + 32-byte offset + 32-byte length = 68 bytes minimum
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

        // string bytes start at position 68 in the payload
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

    receive() external payable {}
}
