// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20MinimalMigration {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title NTEMigrationHelper - Migrates balances from an old token to NTE
/// @notice Reads balances from a previous token contract and sends the same
///         amounts of NTE to those holders as part of a migration, using a
///         provided address list.
contract NTEMigrationHelper {
    address public immutable oldToken;
    address public immutable newToken;
    address public immutable owner;

    /// @notice Tracks which addresses have already been migrated to avoid double migrations.
    mapping(address => bool) public migrated;
    event MigrationExecuted(address indexed holder, uint256 amount);

    /// @notice When true, no further migrations or claims are allowed.
    bool public migrationClosed;

    bool private _entered;

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

    constructor(address _oldToken, address _newToken) {
        require(_oldToken != address(0), "OLD_ZERO");
        require(_newToken != address(0), "NEW_ZERO");
        require(_oldToken != _newToken, "SAME_TOKEN");
        oldToken = _oldToken;
        newToken = _newToken;
        owner = msg.sender;
    }

    /// @notice Returns how many NTE a user can currently claim.
    /// @dev Returns 0 if they already migrated via this helper.
    function getClaimableAmount(address account) public view returns (uint256) {
        if (migrated[account]) {
            return 0;
        }
        return IERC20MinimalMigration(oldToken).balanceOf(account);
    }

    /// @notice Returns the total amount of NTE required to migrate
    ///         for the given holder list based on `oldToken` balances.
    /// @dev Only counts holders that have not been migrated yet.
    function getTotalAmountFromOldBalances(address[] calldata holders) external view returns (uint256 totalAmount) {
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);

        uint256 length = holders.length;
        for (uint256 i = 0; i < length; i++) {
            address holder = holders[i];
            if (holder == address(0)) {
                continue;
            }
            if (migrated[holder]) {
                continue;
            }

            totalAmount += oldT.balanceOf(holder);
        }
    }

    /// @notice Performs a 1:1 migration based on balances of `oldToken`.
    /// @dev The helper must be pre-funded with enough NTE tokens before calling.
    ///      Call this function in batches with a complete list of holder addresses
    ///      collected off-chain from the old token contract.
    /// @param holders List of holder addresses from the previous token.
    function migrateFromOldBalances(address[] calldata holders) external onlyOwner nonReentrant {
        require(!migrationClosed, "MIGRATION_CLOSED");
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);
        IERC20MinimalMigration newT = IERC20MinimalMigration(newToken);

        uint256 length = holders.length;
        for (uint256 i = 0; i < length; i++) {
            address holder = holders[i];
            if (holder == address(0)) {
                continue;
            }
            if (migrated[holder]) {
                continue;
            }

            uint256 amount = oldT.balanceOf(holder);
            migrated[holder] = true;

            if (amount == 0) {
                continue;
            }

            require(newT.transfer(holder, amount), "NTE_TRANSFER_FAIL");
            emit MigrationExecuted(holder, amount);
        }
    }

    /// @notice Claim your migrated NTE based on your old token balance.
    /// @dev Users call this directly; owner just needs to pre-fund NTE here.
    function claim() external nonReentrant {
        require(!migrationClosed, "MIGRATION_CLOSED");
        address account = msg.sender;
        require(!migrated[account], "ALREADY_MIGRATED");

        uint256 amount = IERC20MinimalMigration(oldToken).balanceOf(account);
        require(amount > 0, "NO_BALANCE");

        migrated[account] = true;

        bool ok = IERC20MinimalMigration(newToken).transfer(account, amount);
        require(ok, "NTE_TRANSFER_FAIL");

        emit MigrationExecuted(account, amount);
    }

    /// @notice Owner can trigger a migration claim on behalf of specific users.
    /// @dev Useful for users who cannot or do not claim themselves.
    function claimFor(address[] calldata accounts) external onlyOwner nonReentrant {
        require(!migrationClosed, "MIGRATION_CLOSED");
        IERC20MinimalMigration oldT = IERC20MinimalMigration(oldToken);
        IERC20MinimalMigration newT = IERC20MinimalMigration(newToken);

        uint256 length = accounts.length;
        for (uint256 i = 0; i < length; i++) {
            address account = accounts[i];
            if (account == address(0)) {
                continue;
            }
            if (migrated[account]) {
                continue;
            }

            uint256 amount = oldT.balanceOf(account);
            if (amount == 0) {
                migrated[account] = true; // mark so we don't keep re-checking
                continue;
            }

            migrated[account] = true;
            require(newT.transfer(account, amount), "NTE_TRANSFER_FAIL");

            emit MigrationExecuted(account, amount);
        }
    }

    /// @notice Permanently closes migration. After this, no new claims or migrations are allowed.
    function closeMigration() external onlyOwner {
        migrationClosed = true;
    }

    /// @notice Allows the owner to recover any ERC20 tokens from this helper.
    /// @dev Useful to sweep leftover NTE or other tokens after migration is done.
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "TO_ZERO");
        IERC20MinimalMigration erc20 = IERC20MinimalMigration(token);
        require(erc20.transfer(to, amount), "RESCUE_FAIL");
    }
}
