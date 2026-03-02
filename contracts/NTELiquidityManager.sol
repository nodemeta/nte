// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC20 interface used by the liquidity manager
interface IERC20MinimalLM {
    /// @notice Transfers `amount` tokens to address `to`.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` tokens from address `from` to address `to`.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Returns the token balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Approves `spender` to spend up to `amount` tokens on behalf of the caller.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Returns the remaining allowance from `owner` to `spender`.
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @notice Minimal interface for the main NTE token used for ownership and pause state
interface INTELM is IERC20MinimalLM {
    /// @notice Returns the address of the token owner.
    function owner() external view returns (address);

    /// @notice Returns whether the token is currently paused.
    function paused() external view returns (bool);
}

/// @notice Minimal Pancake router interface used for swaps and adding liquidity
interface IPancakeRouterMinimal {
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

/**
 * @title NTELiquidityManager
 * @notice Receives a portion of NTE tax and manages NTE/BNB liquidity on PancakeSwap.
 *         Pause control is delegated to the main NTE token. Ownership is managed
 *         in this contract via a two-step transfer flow.
 */
contract NTELiquidityManager {
    /// @notice Basis points denominator (100% = 10,000).
    uint256 public constant BASIS_POINTS = 10_000;
    /// @notice Ownership lock period before renouncement and BNB emergency withdraw (30 days).
    uint256 private constant OWNERSHIP_LOCK_PERIOD = 30 days;

    /// @notice The main NTE token this manager works with.
    INTELM public immutable nteToken;
    /// @notice Pancake router used for swaps and adding liquidity.
    IPancakeRouterMinimal public router;
    /// @notice Recipient of LP tokens minted by the router.
    address public lpRecipient;

    /// @notice Whether automatic liquidity cycles are enabled.
    bool public autoOperationsEnabled;
    /// @notice Minimum amount of NTE in this contract required to trigger auto-liquidity.
    uint256 public minTokensToLiquify;
    /// @notice Minimum ETH expected from the auto swap leg.
    uint256 public autoMinEthOut;
    /// @notice Minimum token amount accepted when adding auto-liquidity.
    uint256 public autoAmountTokenMin;
    /// @notice Minimum ETH amount accepted when adding auto-liquidity.
    uint256 public autoAmountETHMin;
    /// @notice Deadline window (seconds) used for auto operations.
    uint256 public autoDeadlineWindow;
    /// @notice If true, only owner and approved keepers can trigger `autoAddLiquidity`.
    bool public autoOnlyKeepers;
    /// @notice Approved keeper addresses for permissioned auto-liquidity calls.
    mapping(address => bool) public autoLiquidityKeeper;

    /// @notice Reentrancy guard status flag.
    uint256 private _status;
    /// @notice Current owner of this manager.
    address private _owner;
    /// @notice Pending owner waiting to accept ownership.
    address private _pendingOwner;
    /// @notice Timestamp when this manager was deployed.
    uint256 public immutable launchTime;

    /// @notice Emitted when manager ownership changes.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when manager ownership transfer is initiated.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when the router address is updated.
    event RouterUpdated(address indexed newRouter);
    /// @notice Emitted when the LP recipient address is updated.
    event LpRecipientUpdated(address indexed newRecipient);
    /// @notice Emitted when automatic operations configuration is updated.
    event AutoOperationsConfigured(bool enabled, uint256 minTokensToLiquify);
    /// @notice Emitted when auto execution safety parameters are updated.
    event AutoExecutionConfigured(
        uint256 minEthOut,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadlineWindow
    );
    /// @notice Emitted when auto-liquidity caller policy is updated.
    event AutoCallerPolicyUpdated(bool onlyKeepers);
    /// @notice Emitted when a keeper address is updated.
    event AutoKeeperUpdated(address indexed keeper, bool allowed);
    /// @notice Emitted whenever new liquidity is added to the pool.
    event LiquidityAdded(uint256 tokenUsed, uint256 ethUsed, uint256 lpMinted);
    /// @notice Emitted after swapping NTE for the native coin (BNB on BSC).
    event TokensSwappedForETH(uint256 amountIn, uint256 ethReceived);
    /// @notice Emitted when ERC20 tokens are rescued from this contract.
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when BNB is rescued from this contract (legacy event name).
    event EmergencyETHWithdraw(address indexed to, uint256 amount);
    /// @notice Emitted when BNB is rescued from this contract.
    event EmergencyBNBWithdraw(address indexed to, uint256 amount);
    /// @notice Emitted when BNB is received.
    event BNBReceived(address indexed sender, uint256 amount);

    // ===================================================
    // ERRORS
    // ===================================================

    error SEC_REENTRY();
    error AUTH_OWNER();
    error AUTH_ZERO_OWNER();
    error AUTH_LOCKED();
    error AUTH_SAME_OWNER();
    error AUTH_NOT_PENDING_OWNER();
    error AUTH_NO_PENDING_TRANSFER();
    error AUTH_AUTO_CALLER();
    error EMG_INVALID_TOKEN();
    error EMG_ZERO_RECIP();
    error EMG_INSUF_BAL();
    error EMG_TRANSFER_FAIL();
    error EMG_WAIT_30D();
    error EMG_INVALID_RECIP();
    error EMG_INSUF_BAL_BNB();
    error EMG_BNB_FAIL();
    error ADDR_ZERO();
    error ADDR_NOT_CONTRACT();
    error CFG_MIN_TOKENS();
    error CFG_SLIPPAGE_ZERO();
    error CFG_DEADLINE_WINDOW();
    error CFG_DEADLINE_EXPIRED();

    /// @notice Restricts function access to manager owner.
    modifier onlyOwner() {
        if (msg.sender != _owner) revert AUTH_OWNER();
        _;
    }

    /// @notice Ensures the main token is not paused before proceeding.
    modifier notPaused() {
        require(!nteToken.paused(), "TOKEN_PAUSED");
        _;
    }

    /// @notice Simple reentrancy guard modifier.
    modifier nonReentrant() {
        if (_status == 2) revert SEC_REENTRY();
        _status = 2;
        _;
        _status = 1;
    }

    /**
     * @notice Deploys a new liquidity manager instance.
     * @dev Initializes the manager with the NTE token, Pancake router, and LP recipient.
     *      The deployer becomes the initial owner and is automatically set as an approved keeper.
     *      Auto-liquidity is restricted to keepers by default for security.
     * @param _nteToken Address of the NTE token.
     * @param _router Address of the Pancake router.
     * @param _lpRecipient Address that will receive LP tokens.
     * @custom:example constructor(0x123...NTE, 0x456...Router, 0x789...LP)
     * @custom:security Validates all addresses are non-zero and token/router are contracts.
     * @custom:reverts ADDR_ZERO if any address is zero.
     * @custom:reverts ADDR_NOT_CONTRACT if NTE or router is not a contract.
     */
    constructor(address _nteToken, address _router, address _lpRecipient) {
        if (_nteToken == address(0)) revert ADDR_ZERO();
        if (_router == address(0)) revert ADDR_ZERO();
        if (_lpRecipient == address(0)) revert ADDR_ZERO();
        if (_nteToken.code.length == 0) revert ADDR_NOT_CONTRACT();
        if (_router.code.length == 0) revert ADDR_NOT_CONTRACT();
        nteToken = INTELM(_nteToken);
        router = IPancakeRouterMinimal(_router);
        lpRecipient = _lpRecipient;
        _owner = msg.sender;
        autoOnlyKeepers = true;
        autoLiquidityKeeper[msg.sender] = true;
        launchTime = block.timestamp;
        _status = 1;
        emit OwnershipTransferred(address(0), msg.sender);
        emit AutoCallerPolicyUpdated(true);
        emit AutoKeeperUpdated(msg.sender, true);
    }

    // ===================================================
    // OWNERSHIP
    // ===================================================

    /**
     * @notice Returns the current manager owner.
     * @dev The owner has exclusive rights to configure liquidity manager settings,
     *      update router/recipient, and perform emergency withdrawals. Ownership can
     *      be transferred via two-step process or renounced after 30 days.
     * @return The address of the owner.
     * @custom:example owner() => 0x123...abc
     * @custom:security Owner is set at construction and can only change via transferOwnership/acceptOwnership.
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice Returns the pending owner in the two-step ownership transfer.
     * @dev Returns address(0) when no ownership transfer is in progress.
     *      The pending owner must call acceptOwnership() to complete the transfer.
     * @return The address of the pending owner, or zero address if no transfer is pending.
     * @custom:example pendingOwner() => 0x456...def (transfer in progress)
     * @custom:example pendingOwner() => 0x000...000 (no pending transfer)
     * @custom:security Two-step ownership prevents accidental transfers to wrong addresses.
     */
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /**
     * @notice Initiates a two-step ownership transfer to a new address.
     * @dev The new owner must call acceptOwnership() to complete the transfer.
     *      This prevents accidental transfers to incorrect or inaccessible addresses.
     *      The current owner can call cancelOwnershipTransfer() before acceptance.
     * @param newOwner The address of the new owner.
     * @custom:example transferOwnership(0x456...def)
     * @custom:security Requires caller to be current owner; prevents transfers to zero or same address.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts AUTH_ZERO_OWNER if newOwner is the zero address.
     * @custom:reverts AUTH_SAME_OWNER if newOwner is already the current owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert AUTH_ZERO_OWNER();
        if (newOwner == _owner) revert AUTH_SAME_OWNER();
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @notice Accepts ownership transfer and completes the two-step ownership change.
     * @dev Only the pending owner can call this function. Once accepted, msg.sender
     *      becomes the new owner and pendingOwner is reset to zero address.
     * @custom:example acceptOwnership() // called by pending owner
     * @custom:security Only callable by the address set in transferOwnership().
     * @custom:reverts AUTH_NOT_PENDING_OWNER if caller is not the pending owner.
     * @custom:usecase Complete ownership transfer after previous owner called transferOwnership().
     */
    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert AUTH_NOT_PENDING_OWNER();
        address previousOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, _owner);
    }

    /**
     * @notice Cancels a pending ownership transfer before the new owner accepts.
     * @dev Resets pendingOwner to zero address, allowing the owner to either keep
     *      ownership or initiate a transfer to a different address.
     * @custom:example cancelOwnershipTransfer() // reverts pending transfer
     * @custom:security Only the current owner can cancel; does not affect current ownership.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts AUTH_NO_PENDING_TRANSFER if there is no pending transfer to cancel.
     * @custom:usecase Cancel mistaken ownership transfer or revoke access before acceptance.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        if (_pendingOwner == address(0)) revert AUTH_NO_PENDING_TRANSFER();
        _pendingOwner = address(0);
        emit OwnershipTransferStarted(_owner, address(0));
    }

    /**
     * @notice Renounces manager ownership permanently, making the contract ownerless.
     * @dev Sets owner to zero address after 30-day lock period for security.
     *      Once renounced, owner-restricted functions (configuration, emergency withdrawals)
     *      become permanently inaccessible. Automatic liquidity operations continue if enabled.
     * @custom:example renounceOwnership() // 31+ days after deployment
     * @custom:security Requires 30 days since launch to prevent accidental early renunciation.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts AUTH_LOCKED if called before launchTime + 30 days.
     * @custom:usecase Decentralize the manager after verifying correct configuration.
     */
    function renounceOwnership() external onlyOwner {
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert AUTH_LOCKED();
        address previousOwner = _owner;
        _owner = address(0);
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }

    /**
     * @notice Updates the Pancake router used for swaps and liquidity.     * @dev Revokes allowance from previous router (if different) for security.
     *      The new router must be a valid contract address.
     * @param _router New router address.
     * @custom:example setRouter(0xABC...newRouter)
     * @custom:security Validates router is non-zero and is a contract; resets old router allowance.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts ADDR_ZERO if router is the zero address.
     * @custom:reverts ADDR_NOT_CONTRACT if router is not a contract.
     * @custom:usecase Update router after PancakeSwap upgrade or migration to new DEX.
     */
    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ADDR_ZERO();
        if (_router.code.length == 0) revert ADDR_NOT_CONTRACT();
        address previousRouter = address(router);
        if (previousRouter != _router) {
            uint256 previousAllowance = nteToken.allowance(address(this), previousRouter);
            if (previousAllowance > 0) {
                require(nteToken.approve(previousRouter, 0), "APPROVE_RESET_FAIL");
            }
        }
        router = IPancakeRouterMinimal(_router);
        emit RouterUpdated(_router);
    }

    /**
     * @notice Updates the LP recipient address.
     * @dev LP tokens minted by the router will be sent to this address.
     *      Typically set to treasury or burn address for permanent liquidity locking.
     * @param _recipient New LP recipient address.
     * @custom:example setLpRecipient(0x456...treasury)
     * @custom:security Validates recipient is non-zero address.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts ADDR_ZERO if recipient is the zero address.
     * @custom:usecase Update LP recipient for treasury management or liquidity locking strategy.
     */
    function setLpRecipient(address _recipient) external onlyOwner {
        if (_recipient == address(0)) revert ADDR_ZERO();
        lpRecipient = _recipient;
        emit LpRecipientUpdated(_recipient);
    }

    /**
     * @notice Configures automatic liquidity operations.
     * @dev When enabled, allows autoAddLiquidity() to execute if minimum threshold is met.
     *      The minimum must be at least 2 tokens to allow 50/50 split for swap and liquidity.
     * @param enabled True to enable auto-liquidity logic.
     * @param _minTokensToLiquify Minimum NTE balance required to trigger a cycle.
     * @custom:example configureAutoOperations(true, 1000e18)
     * @custom:security Enforces minimum of 2 tokens when enabled to prevent division errors.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts CFG_MIN_TOKENS if enabled but minimum is less than 2.
     * @custom:usecase Enable automatic liquidity adding when tax accumulation reaches threshold.
     */
    function configureAutoOperations(bool enabled, uint256 _minTokensToLiquify) external onlyOwner {
        if (enabled) {
            if (_minTokensToLiquify < 2) revert CFG_MIN_TOKENS();
            if (autoMinEthOut == 0 || autoAmountTokenMin == 0 || autoAmountETHMin == 0) revert CFG_SLIPPAGE_ZERO();
            if (autoDeadlineWindow == 0) revert CFG_DEADLINE_WINDOW();
        }
        autoOperationsEnabled = enabled;
        minTokensToLiquify = _minTokensToLiquify;
        emit AutoOperationsConfigured(enabled, _minTokensToLiquify);
    }

    /**
     * @notice Configures auto-liquidity slippage and deadline controls.
     * @dev These parameters protect against sandwich attacks and ensure sufficient output.
     *      All slippage values must be non-zero to prevent accepting zero-output swaps/liquidity.
     * @param minEthOut Minimum ETH output accepted from the swap leg.
     * @param amountTokenMin Minimum token amount accepted in add-liquidity.
     * @param amountETHMin Minimum ETH amount accepted in add-liquidity.
     * @param deadlineWindow Deadline window (seconds) from the current block time.
     * @custom:example configureAutoExecution(0.01 ether, 100e18, 0.005 ether, 300)
     * @custom:security All parameters must be non-zero to prevent accepting unfavorable trades.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts CFG_SLIPPAGE_ZERO if any slippage parameter is zero.
     * @custom:reverts CFG_DEADLINE_WINDOW if deadline window is zero.
     * @custom:usecase Set slippage tolerance and deadline for automated liquidity operations.
     */
    function configureAutoExecution(
        uint256 minEthOut,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadlineWindow
    ) external onlyOwner {
        if (minEthOut == 0 || amountTokenMin == 0 || amountETHMin == 0) revert CFG_SLIPPAGE_ZERO();
        if (deadlineWindow == 0) revert CFG_DEADLINE_WINDOW();
        autoMinEthOut = minEthOut;
        autoAmountTokenMin = amountTokenMin;
        autoAmountETHMin = amountETHMin;
        autoDeadlineWindow = deadlineWindow;
        emit AutoExecutionConfigured(minEthOut, amountTokenMin, amountETHMin, deadlineWindow);
    }

    /**
     * @notice Configures whether auto-liquidity is restricted to owner/approved keepers.
     * @dev When true, only owner and approved keepers can call autoAddLiquidity().
     *      When false, any address can trigger auto-liquidity if conditions are met.
     * @param onlyKeepers True to restrict calls, false to allow any caller.
     * @custom:example setAutoCallerPolicy(false) // allow public automation
     * @custom:security Restricting to keepers provides centralized control; public allows permissionless bots.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:usecase Enable permissionless automation or restrict to trusted keepers.
     */
    function setAutoCallerPolicy(bool onlyKeepers) external onlyOwner {
        autoOnlyKeepers = onlyKeepers;
        emit AutoCallerPolicyUpdated(onlyKeepers);
    }

    /**
     * @notice Grants or revokes keeper permission for `autoAddLiquidity`.
     * @dev Keepers are addresses authorized to call autoAddLiquidity() when autoOnlyKeepers is true.
     *      Owner is automatically a keeper and does not need explicit approval.
     * @param keeper Keeper address.
     * @param allowed True to allow, false to revoke.
     * @custom:example setAutoLiquidityKeeper(0xABC...bot, true)
     * @custom:security Owner can add/remove keepers at any time; validates keeper is non-zero.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts ADDR_ZERO if keeper is the zero address.
     * @custom:usecase Authorize trusted bot addresses or revoke compromised keepers.
     */
    function setAutoLiquidityKeeper(address keeper, bool allowed) external onlyOwner {
        if (keeper == address(0)) revert ADDR_ZERO();
        autoLiquidityKeeper[keeper] = allowed;
        emit AutoKeeperUpdated(keeper, allowed);
    }

    /**
     * @notice Returns the NTE balance currently held by this contract.
     * @dev This is the amount available for liquidity operations. Does not include LP tokens.
     *      Contract receives NTE via tax transfers from the main token contract.
     * @return The NTE token balance available in this manager.
     * @custom:example availableTokenBalance() returns 5000e18 // 5000 NTE available
     * @custom:usecase Check if sufficient tokens accumulated before manual or auto liquidity cycles.
     */
    function availableTokenBalance() public view returns (uint256) {
        return nteToken.balanceOf(address(this));
    }

    /**
     * @dev Ensures the router has enough allowance to move `amount` tokens from this contract.
     *      If current allowance is insufficient, approves max uint256 to avoid repeated approvals.
     *      Optimizes gas by checking current allowance before approving.
     * @param amount The minimum allowance required for the upcoming operation.
     * @custom:security Sets to max uint256 for gas efficiency; router is trusted PancakeSwap contract.
     * @custom:reverts "APPROVE_FAIL" if approval transaction fails.
     */
    function _ensureRouterAllowance(uint256 amount) internal {
        uint256 current = nteToken.allowance(address(this), address(router));
        if (current < amount) {
            // Set to max to avoid repeated approvals
            require(nteToken.approve(address(router), type(uint256).max), "APPROVE_FAIL");
        }
    }

    /**
     * @notice Manually runs a full NTE/BNB liquidity cycle.
     * @dev Splits tokens into two halves, swaps one half for BNB, then
     *      adds liquidity with the remaining tokens and received BNB.
     *      Owner has full control over amounts and slippage for manual operations.
     * @param tokenAmountToLiquify Total NTE amount to use from this contract.
     * @param minEthOut Minimum acceptable BNB output from the swap leg.
     * @param amountTokenMin Minimum acceptable NTE amount used in add-liquidity.
     * @param amountETHMin Minimum acceptable BNB amount used in add-liquidity.
     * @param deadline Unix timestamp deadline used for both router operations.
     * @custom:example runLiquidityCycle(1000e18, 0.1 ether, 400e18, 0.08 ether, block.timestamp + 300)
     * @custom:security Requires owner, validates sufficient balance, enforces non-zero slippage parameters.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts CFG_MIN_TOKENS if amount is less than 2.
     * @custom:reverts CFG_SLIPPAGE_ZERO if any slippage parameter is zero.
     * @custom:reverts CFG_DEADLINE_EXPIRED if deadline is in the past.
     * @custom:reverts "INSUF_TOKENS" if contract doesn't hold enough tokens.
     * @custom:reverts "ROUTER_ZERO" if router is not set.
     * @custom:usecase Manually trigger liquidity addition with custom parameters.
     */
    function runLiquidityCycle(
        uint256 tokenAmountToLiquify,
        uint256 minEthOut,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    ) external onlyOwner notPaused nonReentrant {
        if (tokenAmountToLiquify < 2) revert CFG_MIN_TOKENS();
        if (minEthOut == 0 || amountTokenMin == 0 || amountETHMin == 0) revert CFG_SLIPPAGE_ZERO();
        if (deadline < block.timestamp) revert CFG_DEADLINE_EXPIRED();
        require(tokenAmountToLiquify <= availableTokenBalance(), "INSUF_TOKENS");
        require(address(router) != address(0), "ROUTER_ZERO");

        uint256 half = tokenAmountToLiquify / 2;
        if (half == 0) revert CFG_MIN_TOKENS();
        uint256 otherHalf = tokenAmountToLiquify - half;

        _ensureRouterAllowance(tokenAmountToLiquify);

        uint256 initialEthBalance = address(this).balance;

        _swapTokensForETH(half, minEthOut, deadline);

        uint256 ethReceived = address(this).balance - initialEthBalance;

        emit TokensSwappedForETH(half, ethReceived);

        _addLiquidity(otherHalf, ethReceived, amountTokenMin, amountETHMin, deadline);
    }

    /**
     * @notice Triggers an automatic NTE/BNB liquidity add if the configured
     *         minimum token threshold is met.
     * @dev Can be restricted to owner/approved keepers via `setAutoCallerPolicy`.
     *      Uses pre-configured auto-execution parameters for slippage and deadline.
     *      Silently returns if conditions aren't met (no revert for flexibility).
     * @custom:example autoAddLiquidity() // called by keeper or bot
     * @custom:security Respects keeper restrictions, validates all auto-config parameters set.
     * @custom:reverts AUTH_AUTO_CALLER if caller is not authorized (when autoOnlyKeepers is true).
     * @custom:usecase Permissionless or keeper-triggered automatic liquidity management.
     */
    function autoAddLiquidity() external notPaused nonReentrant {
        if (autoOnlyKeepers && msg.sender != _owner && !autoLiquidityKeeper[msg.sender]) {
            revert AUTH_AUTO_CALLER();
        }
        if (!autoOperationsEnabled) return;
        if (minTokensToLiquify < 2) return;
        if (autoMinEthOut == 0 || autoAmountTokenMin == 0 || autoAmountETHMin == 0) return;
        if (autoDeadlineWindow == 0) return;

        uint256 balance = availableTokenBalance();
        if (balance < minTokensToLiquify) return;

        uint256 amountToUse = minTokensToLiquify;
        if (amountToUse > balance) {
            amountToUse = balance;
        }

        uint256 half = amountToUse / 2;
        if (half == 0) return;
        uint256 otherHalf = amountToUse - half;
        uint256 deadline = block.timestamp + autoDeadlineWindow;

        uint256 initialEthBalance = address(this).balance;

        _ensureRouterAllowance(amountToUse);

        _swapTokensForETH(half, autoMinEthOut, deadline);

        uint256 ethReceived = address(this).balance - initialEthBalance;
        if (ethReceived == 0) return;
        emit TokensSwappedForETH(half, ethReceived);

        _addLiquidity(otherHalf, ethReceived, autoAmountTokenMin, autoAmountETHMin, deadline);
    }

    /**
     * @dev Swaps `tokenAmount` NTE for the native coin (BNB on BSC) via PancakeSwap.
     *      Uses swapExactTokensForETHSupportingFeeOnTransferTokens to handle fee-on-transfer tokens.
     *      Constructs path: NTE -> WETH (WBNB on BSC). Received native coin stays in this contract.
     * @param tokenAmount The amount of NTE tokens to swap.
     * @param minEthOut The minimum acceptable native coin (BNB) output to prevent slippage.
     * @param deadline The unix timestamp deadline; swap must complete before this time.
     * @custom:security Validates non-zero amount and deadline; slippage protection via minEthOut.
     * @custom:reverts "AMOUNT_ZERO" if tokenAmount is zero.
     * @custom:reverts CFG_DEADLINE_EXPIRED if deadline has passed.
     * @custom:reverts PancakeRouter errors if slippage exceeds tolerance or liquidity insufficient.
     */
    function _swapTokensForETH(uint256 tokenAmount, uint256 minEthOut, uint256 deadline) internal {
        require(tokenAmount > 0, "AMOUNT_ZERO");
        if (deadline < block.timestamp) revert CFG_DEADLINE_EXPIRED();

        address[] memory path = new address[](2);
        path[0] = address(nteToken);
        path[1] = router.WETH();

        // Caller must ensure router has allowance from this contract in deployment or ops scripts.
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            minEthOut,
            path,
            address(this),
            deadline
        );
    }

    /**
     * @dev Adds NTE/BNB liquidity to PancakeSwap using the router, sending LP tokens to `lpRecipient`.
     *      Validates all parameters including non-zero slippage minimums and valid recipient.
     *      Uses native coin (BNB) held in contract balance from previous swap operation.
     * @param tokenAmount The amount of NTE tokens to add to liquidity pool.
     * @param ethAmount The amount of native coin (BNB) to add to liquidity pool.
     * @param amountTokenMin The minimum NTE amount accepted (slippage protection).
     * @param amountETHMin The minimum BNB amount accepted (slippage protection).
     * @param deadline The unix timestamp deadline; operation must complete before this time.
     * @custom:security Validates non-zero amounts and recipient; slippage protection prevents unfavorable ratios.
     * @custom:reverts "AMOUNT_ZERO" if tokenAmount is zero.
     * @custom:reverts "ETH_ZERO" if ethAmount is zero.
     * @custom:reverts "RECIP_ZERO" if lpRecipient is zero address.
     * @custom:reverts CFG_SLIPPAGE_ZERO if any slippage minimum is zero.
     * @custom:reverts CFG_DEADLINE_EXPIRED if deadline has passed.
     * @custom:reverts PancakeRouter errors if slippage exceeded or insufficient liquidity.
     */
    function _addLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    ) internal {
        require(tokenAmount > 0, "AMOUNT_ZERO");
        require(ethAmount > 0, "ETH_ZERO");
        require(lpRecipient != address(0), "RECIP_ZERO");
        if (amountTokenMin == 0 || amountETHMin == 0) revert CFG_SLIPPAGE_ZERO();
        if (deadline < block.timestamp) revert CFG_DEADLINE_EXPIRED();

        // Caller must ensure router has allowance from this contract in deployment or ops scripts.
        (uint256 usedToken, uint256 usedEth, uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            address(nteToken),
            tokenAmount,
            amountTokenMin,
            amountETHMin,
            lpRecipient,
            deadline
        );

        emit LiquidityAdded(usedToken, usedEth, liquidity);
    }

    /**
     * @notice Emergency function to withdraw stuck ERC20 tokens from the contract.
     * @dev Recovers any ERC20 tokens accidentally sent to this manager contract.
     *      Uses low-level call to handle non-standard ERC20 implementations.
     *      Can withdraw NTE tokens if accidentally over-funded.
     * @param token The address of the ERC20 token to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     * @param amount The number of tokens to withdraw.
     * @custom:example emergencyWithdrawToken(0xABC...token, 0x456...recipient, 1000e18)
     * @custom:security Validates addresses and balance before transfer; owner-only access.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts SEC_REENTRY on reentrant call attempts.
     * @custom:reverts EMG_INVALID_TOKEN if token is zero address.
     * @custom:reverts EMG_ZERO_RECIP if recipient is zero address.
     * @custom:reverts EMG_INSUF_BAL if contract balance is less than requested amount.
     * @custom:reverts EMG_TRANSFER_FAIL if the token transfer fails.
     * @custom:usecase Recover tokens sent to manager by mistake or rescue over-funded NTE.
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0)) revert EMG_INVALID_TOKEN();
        if (to == address(0)) revert EMG_ZERO_RECIP();

        uint256 contractBalance = IERC20MinimalLM(token).balanceOf(address(this));
        if (contractBalance < amount) revert EMG_INSUF_BAL();

        bytes memory payload = abi.encodeWithSelector(IERC20MinimalLM.transfer.selector, to, amount);
        (bool success, bytes memory returndata) = token.call(payload);
        if (!success) revert EMG_TRANSFER_FAIL();
        if (returndata.length > 0) {
            if (!abi.decode(returndata, (bool))) revert EMG_TRANSFER_FAIL();
        }
        emit EmergencyTokenWithdraw(token, to, amount);
    }

    /**
     * @notice Emergency function to withdraw BNB from the contract.
     * @dev Recovers native BNB accidentally sent to this manager contract.
     *      Requires 30 days since launch to prevent premature withdrawals during setup.
     *      Leftover BNB from liquidity operations can be recovered.
     * @param to The recipient address for the withdrawn BNB.
     * @param amount The amount of BNB (in wei) to withdraw.
     * @custom:example emergencyWithdrawBNB(payable(0x456...recipient), 1 ether)
     * @custom:security 30-day lock prevents owner from immediately draining accidentally sent funds.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts SEC_REENTRY on reentrant call attempts.
     * @custom:reverts EMG_WAIT_30D if called before launchTime + 30 days.
     * @custom:reverts EMG_INVALID_RECIP if recipient is zero address.
     * @custom:reverts EMG_INSUF_BAL_BNB if contract balance is less than requested amount.
     * @custom:reverts EMG_BNB_FAIL if the BNB transfer fails.
     * @custom:usecase Recover BNB sent to manager by mistake after 30-day safety period.
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        _emergencyWithdrawNative(to, amount);
    }

    /**
     * @notice Emergency function to withdraw BNB from this contract.
     * @dev Legacy alias for `emergencyWithdrawBNB`. Maintains backward compatibility.
     *      Subject to same 30-day lock period and validations as emergencyWithdrawBNB().
     * @param to Recipient address for the withdrawn BNB.
     * @param amount Amount of BNB (in wei) to withdraw.
     * @custom:example emergencyWithdrawETH(payable(0x456...recipient), 1 ether)
     * @custom:security Identical security constraints as emergencyWithdrawBNB(); 30-day delay enforced.
     * @custom:reverts AUTH_OWNER if caller is not the owner.
     * @custom:reverts SEC_REENTRY on reentrant call attempts.
     * @custom:reverts EMG_WAIT_30D if called before launchTime + 30 days.
     * @custom:reverts EMG_INVALID_RECIP if recipient is zero address.
     * @custom:reverts EMG_INSUF_BAL_BNB if contract balance is less than requested amount.
     * @custom:reverts EMG_BNB_FAIL if the BNB transfer fails.
     * @custom:usecase Legacy function name; use emergencyWithdrawBNB() for clarity.
     */
    function emergencyWithdrawETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        _emergencyWithdrawNative(to, amount);
    }

    /**
     * @dev Shared native coin emergency withdraw logic for BNB operations.
     *      Validates 30-day lock period, recipient address, balance, and transfer success.
     *      Emits both legacy (EmergencyETHWithdraw) and current (EmergencyBNBWithdraw) events.
     * @param to Recipient address for the withdrawn native coin (BNB).
     * @param amount Amount of native coin (in wei) to withdraw.
     * @custom:security 30-day time lock prevents premature withdrawals after deployment.
     * @custom:reverts EMG_WAIT_30D if called before launchTime + OWNERSHIP_LOCK_PERIOD.
     * @custom:reverts EMG_INVALID_RECIP if recipient is zero address.
     * @custom:reverts EMG_INSUF_BAL_BNB if contract's BNB balance is less than amount.
     * @custom:reverts EMG_BNB_FAIL if low-level BNB transfer call fails.
     */
    function _emergencyWithdrawNative(address payable to, uint256 amount) internal {
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert EMG_WAIT_30D();
        if (to == address(0)) revert EMG_INVALID_RECIP();
        if (amount > address(this).balance) revert EMG_INSUF_BAL_BNB();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert EMG_BNB_FAIL();
        emit EmergencyETHWithdraw(to, amount);
        emit EmergencyBNBWithdraw(to, amount);
    }

    /**
     * @notice Allows this contract to receive BNB from router swaps and other sources.
     * @dev Required for receiving BNB from PancakeSwap router during swapExactTokensForETH operations.
     *      Also accepts direct BNB transfers. Emits BNBReceived event for tracking.
     * @custom:example Automatically called when router sends BNB after swap
     * @custom:usecase Receive BNB from PancakeSwap swaps for subsequent liquidity addition.
     */
    receive() external payable {
        emit BNBReceived(msg.sender, msg.value);
    }
}
