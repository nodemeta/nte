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
     * @param _nteToken Address of the NTE token.
     * @param _router Address of the Pancake router.
     * @param _lpRecipient Address that will receive LP tokens.
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

    /// @notice Returns the current manager owner.
    function owner() external view returns (address) {
        return _owner;
    }

    /// @notice Returns the pending owner.
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /**
     * @notice Transfers manager ownership to a new address.
     * @dev Initiates a two-step ownership transfer.
     * @param newOwner The address of the new owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert AUTH_ZERO_OWNER();
        if (newOwner == _owner) revert AUTH_SAME_OWNER();
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @notice Accepts ownership transfer.
     * @dev Can only be called by the pending owner.
     */
    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert AUTH_NOT_PENDING_OWNER();
        address previousOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, _owner);
    }

    /**
     * @notice Cancels a pending ownership transfer.
     * @dev Can only be called by current owner.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        if (_pendingOwner == address(0)) revert AUTH_NO_PENDING_TRANSFER();
        _pendingOwner = address(0);
        emit OwnershipTransferStarted(_owner, address(0));
    }

    /**
     * @notice Renounces manager ownership.
     * @dev Only possible 30 days after deployment.
     */
    function renounceOwnership() external onlyOwner {
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert AUTH_LOCKED();
        address previousOwner = _owner;
        _owner = address(0);
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }

    /**
     * @notice Updates the Pancake router used for swaps and liquidity.
     * @dev Only callable by manager owner.
     * @param _router New router address.
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
     * @dev LP tokens minted by the router will be sent here.
     * @param _recipient New LP recipient address.
     */
    function setLpRecipient(address _recipient) external onlyOwner {
        if (_recipient == address(0)) revert ADDR_ZERO();
        lpRecipient = _recipient;
        emit LpRecipientUpdated(_recipient);
    }

    /**
     * @notice Configures automatic liquidity operations.
     * @param enabled True to enable auto-liquidity logic.
     * @param _minTokensToLiquify Minimum NTE balance required to trigger a cycle.
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
     * @param minEthOut Minimum ETH output accepted from the swap leg.
     * @param amountTokenMin Minimum token amount accepted in add-liquidity.
     * @param amountETHMin Minimum ETH amount accepted in add-liquidity.
     * @param deadlineWindow Deadline window (seconds) from the current block time.
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
     * @param onlyKeepers True to restrict calls, false to allow any caller.
     */
    function setAutoCallerPolicy(bool onlyKeepers) external onlyOwner {
        autoOnlyKeepers = onlyKeepers;
        emit AutoCallerPolicyUpdated(onlyKeepers);
    }

    /**
     * @notice Grants or revokes keeper permission for `autoAddLiquidity`.
     * @param keeper Keeper address.
     * @param allowed True to allow, false to revoke.
     */
    function setAutoLiquidityKeeper(address keeper, bool allowed) external onlyOwner {
        if (keeper == address(0)) revert ADDR_ZERO();
        autoLiquidityKeeper[keeper] = allowed;
        emit AutoKeeperUpdated(keeper, allowed);
    }

    /// @notice Returns the NTE balance currently held by this contract.
    function availableTokenBalance() public view returns (uint256) {
        return nteToken.balanceOf(address(this));
    }

    /// @dev Ensures the router has enough allowance to move `amount` tokens from this contract.
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
     * @param tokenAmountToLiquify Total NTE amount to use from this contract.
     * @param minEthOut Minimum acceptable BNB output from the swap leg.
     * @param amountTokenMin Minimum acceptable NTE amount used in add-liquidity.
     * @param amountETHMin Minimum acceptable BNB amount used in add-liquidity.
     * @param deadline Unix timestamp deadline used for both router operations.
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

    /// @dev Swaps `tokenAmount` NTE for the native coin (BNB on BSC).
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

    /// @dev Adds NTE/BNB liquidity using the router, sending LP tokens to `lpRecipient`.
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
     * @notice Emergency function to withdraw arbitrary ERC20 tokens from this contract.
     * @dev Owner-controlled; can withdraw NTE, LP tokens, or any other ERC20.
     * @param token Address of the token to withdraw.
     * @param to Recipient address.
     * @param amount Amount to withdraw.
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
     * @notice Emergency function to withdraw BNB from this contract.
     * @dev Only possible 30 days after deployment.
     * @param to Recipient address.
     * @param amount Amount of BNB to withdraw.
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        _emergencyWithdrawNative(to, amount);
    }

    /**
     * @notice Emergency function to withdraw BNB from this contract.
     * @dev Legacy alias for `emergencyWithdrawBNB`.
     * @param to Recipient address.
     * @param amount Amount of BNB to withdraw.
     */
    function emergencyWithdrawETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        _emergencyWithdrawNative(to, amount);
    }

    /// @dev Shared native coin emergency withdraw logic.
    function _emergencyWithdrawNative(address payable to, uint256 amount) internal {
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert EMG_WAIT_30D();
        if (to == address(0)) revert EMG_INVALID_RECIP();
        if (amount > address(this).balance) revert EMG_INSUF_BAL_BNB();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert EMG_BNB_FAIL();
        emit EmergencyETHWithdraw(to, amount);
        emit EmergencyBNBWithdraw(to, amount);
    }

    receive() external payable {
        emit BNBReceived(msg.sender, msg.value);
    }
}
