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
 *         Ownership and pause control are delegated to the main NTE token so there is
 *         a single admin/key that governs both token and liquidity behavior.
 */
contract NTELiquidityManager {
    /// @notice Basis points denominator (100% = 10,000).
    uint256 public constant BASIS_POINTS = 10_000;

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

    /// @notice Reentrancy guard status flag.
    uint256 private _status;

    /// @notice Emitted when the router address is updated.
    event RouterUpdated(address indexed newRouter);
    /// @notice Emitted when the LP recipient address is updated.
    event LpRecipientUpdated(address indexed newRecipient);
    /// @notice Emitted when automatic operations configuration is updated.
    event AutoOperationsConfigured(bool enabled, uint256 minTokensToLiquify);
    /// @notice Emitted whenever new liquidity is added to the pool.
    event LiquidityAdded(uint256 tokenUsed, uint256 ethUsed, uint256 lpMinted);
    /// @notice Emitted after swapping NTE for the native coin (BNB on BSC).
    event TokensSwappedForETH(uint256 amountIn, uint256 ethReceived);
    /// @notice Emitted when ERC20 tokens are rescued from this contract.
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when BNB is rescued from this contract.
    event EmergencyETHWithdraw(address indexed to, uint256 amount);

    /// @notice Restricts function access to the owner of the NTE token.
    modifier onlyOwner() {
        require(msg.sender == nteToken.owner(), "NOT_OWNER");
        _;
    }

    /// @notice Ensures the main token is not paused before proceeding.
    modifier notPaused() {
        require(!nteToken.paused(), "TOKEN_PAUSED");
        _;
    }

    /// @notice Simple reentrancy guard modifier.
    modifier nonReentrant() {
        require(_status != 2, "REENTRANT");
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
        require(_nteToken != address(0), "TOKEN_ZERO");
        require(_router != address(0), "ROUTER_ZERO");
        require(_lpRecipient != address(0), "RECIP_ZERO");
        nteToken = INTELM(_nteToken);
        router = IPancakeRouterMinimal(_router);
        lpRecipient = _lpRecipient;
        _status = 1;
    }

    /**
     * @notice Updates the Pancake router used for swaps and liquidity.
     * @dev Only callable by the NTE owner.
     * @param _router New router address.
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "ROUTER_ZERO");
        router = IPancakeRouterMinimal(_router);
        emit RouterUpdated(_router);
    }

    /**
     * @notice Updates the LP recipient address.
     * @dev LP tokens minted by the router will be sent here.
     * @param _recipient New LP recipient address.
     */
    function setLpRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "RECIP_ZERO");
        lpRecipient = _recipient;
        emit LpRecipientUpdated(_recipient);
    }

    /**
     * @notice Configures automatic liquidity operations.
     * @param enabled True to enable auto-liquidity logic.
     * @param _minTokensToLiquify Minimum NTE balance required to trigger a cycle.
     */
    function configureAutoOperations(bool enabled, uint256 _minTokensToLiquify) external onlyOwner {
        autoOperationsEnabled = enabled;
        minTokensToLiquify = _minTokensToLiquify;
        emit AutoOperationsConfigured(enabled, _minTokensToLiquify);
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
     */
    function runLiquidityCycle(uint256 tokenAmountToLiquify, uint256 minEthOut) external onlyOwner notPaused nonReentrant {
        require(tokenAmountToLiquify > 0, "AMOUNT_ZERO");
        require(tokenAmountToLiquify <= availableTokenBalance(), "INSUF_TOKENS");
        require(address(router) != address(0), "ROUTER_ZERO");

        uint256 half = tokenAmountToLiquify / 2;
        uint256 otherHalf = tokenAmountToLiquify - half;

        _ensureRouterAllowance(tokenAmountToLiquify);

        uint256 initialEthBalance = address(this).balance;

        _swapTokensForETH(half, minEthOut);

        uint256 ethReceived = address(this).balance - initialEthBalance;

        emit TokensSwappedForETH(half, ethReceived);

        _addLiquidity(otherHalf, ethReceived);
    }

    /**
    * @notice Triggers an automatic NTE/BNB liquidity add if the configured
     *         minimum token threshold is met.
     * @dev Can be called by anyone (e.g., a simple bot or keeper service).
     */
    function autoAddLiquidity() external notPaused nonReentrant {
        if (!autoOperationsEnabled) return;
        if (minTokensToLiquify == 0) return;

        uint256 balance = availableTokenBalance();
        if (balance < minTokensToLiquify) return;

        uint256 amountToUse = minTokensToLiquify;
        if (amountToUse > balance) {
            amountToUse = balance;
        }

        uint256 half = amountToUse / 2;
        uint256 otherHalf = amountToUse - half;

        uint256 initialEthBalance = address(this).balance;

        _ensureRouterAllowance(amountToUse);

        _swapTokensForETH(half, 0);

        uint256 ethReceived = address(this).balance - initialEthBalance;
        emit TokensSwappedForETH(half, ethReceived);

        _addLiquidity(otherHalf, ethReceived);
    }

    /// @dev Swaps `tokenAmount` NTE for the native coin (BNB on BSC).
    function _swapTokensForETH(uint256 tokenAmount, uint256 minEthOut) internal {
        require(tokenAmount > 0, "AMOUNT_ZERO");

        address[] memory path = new address[](2);
        path[0] = address(nteToken);
        path[1] = router.WETH();

        // Caller must ensure router has allowance from this contract in deployment or ops scripts.
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            minEthOut,
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Adds NTE/BNB liquidity using the router, sending LP tokens to `lpRecipient`.
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        require(tokenAmount > 0, "AMOUNT_ZERO");
        require(ethAmount > 0, "ETH_ZERO");
        require(lpRecipient != address(0), "RECIP_ZERO");

        // Caller must ensure router has allowance from this contract in deployment or ops scripts.
        (uint256 usedToken, uint256 usedEth, uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            address(nteToken),
            tokenAmount,
            0,
            0,
            lpRecipient,
            block.timestamp
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
        require(to != address(0), "TO_ZERO");
        IERC20MinimalLM erc20 = IERC20MinimalLM(token);
        require(erc20.transfer(to, amount), "TRANSFER_FAIL");
        emit EmergencyTokenWithdraw(token, to, amount);
    }

    /**
     * @notice Emergency function to withdraw BNB from this contract.
     * @param to Recipient address.
     * @param amount Amount of BNB to withdraw.
     */
    function emergencyWithdrawETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "TO_ZERO");
        require(amount <= address(this).balance, "INSUF_ETH");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH_FAIL");
        emit EmergencyETHWithdraw(to, amount);
    }

    receive() external payable {}
}
