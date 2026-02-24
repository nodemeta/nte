// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC20 interface for emergency token recovery
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Minimal interface for NTE categorized transfers
interface INTECategorized {
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
    ) external returns (bool);
}

/**
 * @title NTECategoryHelper
 * @notice UI/helper contract that exposes friendly function names for
 *         categorized transfers and forwards them into the main NTE token.
 *         All business logic, taxes, protections, and state remain in NTE.
 */
contract NTECategoryHelper {
    /// @notice The NTE token this helper forwards calls to.
    INTECategorized public immutable nte;

    /// @notice The current owner of this contract.
    address private _owner;

    /// @notice The pending owner waiting to accept ownership.
    address private _pendingOwner;

    /// @notice Internal guard to prevent re-entry attacks.
    bool private _entered;

    /// @notice Timestamp when this contract was deployed.
    uint256 public immutable launchTime;

    /// @notice Ownership lock period before renouncement (30 days).
    uint256 private constant OWNERSHIP_LOCK_PERIOD = 30 days;

    // ===================================================
    // EVENTS
    // ===================================================

    /// @notice Emitted when contract ownership changes.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when ownership transfer is initiated.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when ERC20 tokens are emergency-withdrawn.
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when BNB is emergency-withdrawn.
    event EmergencyBNBWithdraw(address indexed to, uint256 amount);

    // ===================================================
    // MODIFIERS
    // ===================================================

    modifier onlyOwner() {
        if (msg.sender != _owner) revert AUTH_OWNER();
        _;
    }

    modifier nonReentrant() {
        if (_entered) revert SEC_REENTRY();
        _entered = true;
        _;
        _entered = false;
    }

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
    error EMG_INVALID_TOKEN();
    error EMG_ZERO_RECIP();
    error EMG_INSUF_BAL();
    error EMG_TRANSFER_FAIL();
    error EMG_WAIT_30D();
    error EMG_INVALID_RECIP();
    error EMG_INSUF_BAL_BNB();
    error EMG_BNB_FAIL();
    error ADDR_ZERO();

    // ===================================================
    // CONSTRUCTOR
    // ===================================================

    /**
     * @param _nte Address of the deployed NTE token.
     */
    constructor(address _nte) {
        if (_nte == address(0)) revert ADDR_ZERO();
        nte = INTECategorized(_nte);
        _owner = msg.sender;
        launchTime = block.timestamp;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Allows the contract to receive BNB.
    receive() external payable {}

    // ===================================================
    // OWNERSHIP
    // ===================================================

    /**
     * @notice Returns the address of the current contract owner.
     * @return The address of the owner.
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice Returns the address of the pending owner.
     * @return The address of the pending owner, or zero address if no transfer is pending.
     */
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /**
     * @notice Transfers contract ownership to a new address.
     * @dev Initiates a two-step ownership transfer. The new owner must call acceptOwnership() to complete the transfer.
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
     * @dev Can only be called by the pending owner to complete the two-step transfer process.
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
     * @dev Can only be called by the current owner.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        if (_pendingOwner == address(0)) revert AUTH_NO_PENDING_TRANSFER();
        _pendingOwner = address(0);
        emit OwnershipTransferStarted(_owner, address(0));
    }

    /**
     * @notice Renounces contract ownership, making the contract ownerless.
     * @dev Only possible 30 days after launch for security.
     */
    function renounceOwnership() external onlyOwner {
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert AUTH_LOCKED();
        address previousOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }

    // ===================================================
    // EMERGENCY RECOVERY
    // ===================================================

    /**
     * @notice Emergency function to withdraw stuck ERC20 tokens from the contract.
     * @dev Can withdraw any ERC20 token held by this contract.
     * @param token The address of the token to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0)) revert EMG_INVALID_TOKEN();
        if (to == address(0)) revert EMG_ZERO_RECIP();
        
        // Check contract has sufficient balance
        uint256 contractBalance = IERC20Minimal(token).balanceOf(address(this));
        if (contractBalance < amount) revert EMG_INSUF_BAL();
        
        // Use low-level call to handle non-standard ERC20 tokens
        bytes memory payload = abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount);
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
        if (block.timestamp <= launchTime + OWNERSHIP_LOCK_PERIOD) revert EMG_WAIT_30D();
        if (to == address(0)) revert EMG_INVALID_RECIP();
        if (amount > address(this).balance) revert EMG_INSUF_BAL_BNB();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert EMG_BNB_FAIL();
        
        emit EmergencyBNBWithdraw(to, amount);
    }

    /// @notice Generic categorized transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Payment" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Reward" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Bonus" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Payout" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Deposit" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Withdrawal" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Purchase" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Refund" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Fee" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Subscription" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Sell" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Gift" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Others" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Airdrop" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Mint"-related transfer (e.g. game/NFT mint fee).
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Royalty" payment.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Incentive" payment.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Penalty" deduction.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Cashback" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Swap" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Bridge" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Escrow" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Loan" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Repayment" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Rent" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Level-Up Reward" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Move-to-Earn Reward" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Tournament Prize" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Governance Voting Fee" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Card Payment" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Salary" payment.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Staking Reward" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Farming Reward" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Lottery Prize" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Charity" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Donation" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Tip" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Partner Payment" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Referral Bonus Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Core Node Purchase" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Elite Node Purchase" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Core Node Bonus Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Elite Node Bonus Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Staking Purchase" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Staking Bonus Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Meta Pulse Purchase" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "Meta Pulse Bonus Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "DBE Purchase" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }

    /// @notice Alias for a categorized "DBE Bonus Claim" transfer.
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
        return nte.transactionFrom(msg.sender, to, amount, category, signature, nonce, deadline, txReference, memo);
    }
}
