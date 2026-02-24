// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20Minimal {
    /// @notice Transfers `amount` tokens to address `to`.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Returns the token balance of `account`.
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal interface for the main NTE token used for pause state and staking locks
interface INTE is IERC20Minimal {
    /// @notice Returns the address of the token owner.
    function owner() external view returns (address);

    /// @notice Returns whether the token is currently paused.
    function paused() external view returns (bool);

    /// @notice Locks `amount` tokens for `user` inside the main token contract.
    function lockFromStaking(address user, uint256 amount) external;

    /// @notice Unlocks `amount` tokens for `user` inside the main token contract.
    function unlockFromStaking(address user, uint256 amount) external;

}

/**
 * @title NTEStaking - Time-locked, multi-plan staking for NTE
 * @notice Users can stake NTE into different lockup plans (e.g. 30 days, 90 days)
 *         and earn rewards in NTE. User principal stays in the main NTE token
 *         contract (balances are locked there), and rewards are paid from this
 *         contract's NTE balance.
 */
contract NTEStaking {
    // ===================================================
    // TYPES
    // ===================================================

    struct LockPlan {
        /// @notice Lock duration for this plan in seconds.
        uint256 lockDuration;
        /// @notice APR for this plan in basis points (1000 = 10%).
        uint256 aprBps;
        /// @notice Whether the plan is available for new stakes.
        bool enabled;
    }

    struct StakePosition {
        /// @notice Address that owns this stake.
        address user;
        /// @notice Current lock plan identifier for this stake.
        uint256 planId;
        /// @notice Staked NTE amount including any compounded rewards.
        uint256 amount;
        /// @notice Timestamp when the current lock period started.
        uint256 startTime;
        /// @notice Lock duration fixed for this stake at creation or extension.
        uint256 lockDuration;
        /// @notice APR fixed for this stake at creation or extension.
        uint256 aprBps;
        /// @notice Total rewards that have already been claimed.
        uint256 claimedReward;
        /// @notice Whether the principal has been fully withdrawn.
        bool    withdrawn;
    }

    /// @notice Read-only view struct for returning plan data with names.
    struct LockPlanInfo {
        uint256 planId;
        uint256 lockDuration;
        uint256 aprBps;
        bool enabled;
        string name;
    }

    /// @notice Read-only view struct for returning user stake data with plan names.
    struct UserStakeInfo {
        uint256 stakeId;
        uint256 planId;
        string planName;
        uint256 amount;
        uint256 startTime;
        uint256 lockDuration;
        uint256 aprBps;
        uint256 claimedReward;
        bool withdrawn;
        uint256 pendingReward;
    }

    // ===================================================
    // CONSTANTS
    // ===================================================

    /// @notice Basis points denominator (100% = 10,000).
    uint256 public constant BASIS_POINTS = 10_000;
    /// @notice Number of seconds in one year, used for APR calculations.
    uint256 public constant YEAR_IN_SECONDS = 365 days;
    /// @notice Ownership lock period before allowing renounce / BNB emergency withdraw.
    uint256 private constant OWNERSHIP_LOCK_PERIOD = 30 days;

    // ===================================================
    // STATE
    // ===================================================

    /// @notice The NTE token used for staking, ownership, and pause state.
    INTE public immutable stakingToken;
    /// @notice Current owner of the staking contract.
    address private _owner;
    /// @notice Pending owner in the two-step ownership transfer flow.
    address private _pendingOwner;
    /// @notice Deployment timestamp used for ownership/withdrawal lock periods.
    uint256 public immutable launchTime;

    LockPlan[] public lockPlans;

    /// @notice Optional human-readable names for each staking plan (e.g. "30d 10% APR").
    mapping(uint256 => string) public stakePlanNames;

    mapping(uint256 => StakePosition) public stakes;
    mapping(address => uint256[]) public userStakeIds;

    uint256 public nextStakeId = 1;

    bool public depositsEnabled = true;

    uint256 public totalStaked;

    // ===================================================
    // EVENTS
    // ===================================================

    event PlanAdded(uint256 indexed planId, uint256 lockDuration, uint256 aprBps);
    event PlanUpdated(uint256 indexed planId, uint256 lockDuration, uint256 aprBps, bool enabled);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    event Staked(address indexed user, uint256 indexed stakeId, uint256 indexed planId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed stakeId, uint256 principal, uint256 reward);
    event PrincipalWithdrawn(address indexed user, uint256 indexed stakeId, uint256 principal);
    event EmergencyWithdraw(address indexed user, uint256 indexed stakeId, uint256 principal);

    event DepositsEnabledUpdated(bool enabled);
    event RewardCompounded(address indexed user, uint256 indexed stakeId, uint256 amount);
    event StakePlanExtended(address indexed user, uint256 indexed stakeId, uint256 fromPlanId, uint256 toPlanId);
    event EmergencyTokenWithdraw(address indexed token, address indexed to, uint256 amount);
    event EmergencyBNBWithdraw(address indexed to, uint256 amount);
    event BNBReceived(address indexed sender, uint256 amount);

    // ===================================================
    // MODIFIERS
    // ===================================================

    modifier onlyOwner() {
        require(msg.sender == _owner, "NOT_OWNER");
        _;
    }

    modifier notPaused() {
        // Staking is considered paused whenever the main NTE token is paused
        require(!stakingToken.paused(), "TOKEN_PAUSED");
        _;
    }

    modifier validPlan(uint256 planId) {
        require(planId < lockPlans.length, "INVALID_PLAN");
        _;
    }

    uint256 private _status;
    modifier nonReentrant() {
        require(_status != 2, "REENTRANT");
        _status = 2;
        _;
        _status = 1;
    }

    // ===================================================
    // CONSTRUCTOR
    // ===================================================

    constructor(address _stakingToken) {
        require(_stakingToken != address(0), "TOKEN_ZERO");
        require(_stakingToken.code.length > 0, "TOKEN_NOT_CONTRACT");
        stakingToken = INTE(_stakingToken);
        address initialOwner = stakingToken.owner();
        require(initialOwner != address(0), "OWNER_ZERO");
        _owner = initialOwner;
        launchTime = block.timestamp;
        _status = 1;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    // ===================================================
    // VIEW FUNCTIONS
    // ===================================================

    /// @notice Returns the number of configured lock plans.
    function getPlansCount() external view returns (uint256) {
        return lockPlans.length;
    }

    /// @notice Returns the staking contract owner.
    function owner() external view returns (address) {
        return _owner;
    }

    /// @notice Returns the pending owner in a two-step ownership transfer.
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /// @notice Returns all stake IDs owned by `user`.
    function getUserStakeIds(address user) external view returns (uint256[] memory) {
        return userStakeIds[user];
    }

    /// @notice Returns the current NTE balance held by this contract for rewards.
    function rewardPoolBalance() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    /// @notice Returns all staking plans with their configuration and optional names.
    function getAllStakePlans() external view returns (LockPlanInfo[] memory) {
        uint256 length = lockPlans.length;
        LockPlanInfo[] memory plans = new LockPlanInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            LockPlan storage plan = lockPlans[i];
            plans[i] = LockPlanInfo({
                planId: i,
                lockDuration: plan.lockDuration,
                aprBps: plan.aprBps,
                enabled: plan.enabled,
                name: stakePlanNames[i]
            });
        }
        return plans;
    }

    /**
     * @notice Returns all stake positions owned by `user`.
     */
    function getUserPositions(address user) external view returns (StakePosition[] memory) {
        uint256[] storage ids = userStakeIds[user];
        StakePosition[] memory positions = new StakePosition[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            positions[i] = stakes[ids[i]];
        }
        return positions;
    }

    /// @notice Returns the total principal currently staked (locked) by `user` across all active stakes.
    function userTotalStaked(address user) external view returns (uint256) {
        uint256[] storage ids = userStakeIds[user];
        uint256 total;
        for (uint256 i = 0; i < ids.length; i++) {
            StakePosition storage pos = stakes[ids[i]];
            if (pos.user == user && !pos.withdrawn) {
                total += pos.amount;
            }
        }
        return total;
    }

    /// @notice Returns the total pending rewards across all active stakes owned by `user`.
    function userTotalPendingRewards(address user) external view returns (uint256) {
        uint256[] storage ids = userStakeIds[user];
        uint256 total;
        for (uint256 i = 0; i < ids.length; i++) {
            StakePosition storage pos = stakes[ids[i]];
            if (pos.user != user || pos.withdrawn) {
                continue;
            }
            uint256 reward = pendingReward(ids[i]);
            if (reward > 0) {
                total += reward;
            }
        }
        return total;
    }

    /// @notice Returns all stakes for `user` including plan names and current pending rewards.
    function getUserStakeInfo(address user) external view returns (UserStakeInfo[] memory) {
        uint256[] storage ids = userStakeIds[user];
        uint256 length = ids.length;
        UserStakeInfo[] memory info = new UserStakeInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            uint256 stakeId = ids[i];
            StakePosition storage pos = stakes[stakeId];
            uint256 planId = pos.planId;
            info[i] = UserStakeInfo({
                stakeId: stakeId,
                planId: planId,
                planName: stakePlanNames[planId],
                amount: pos.amount,
                startTime: pos.startTime,
                lockDuration: pos.lockDuration,
                aprBps: pos.aprBps,
                claimedReward: pos.claimedReward,
                withdrawn: pos.withdrawn,
                pendingReward: pendingReward(stakeId)
            });
        }
        return info;
    }

    /// @notice Returns the unclaimed reward for a given stake.
    /// @dev Rewards stop accruing at the earlier of lock end or the current time.
    function pendingReward(uint256 stakeId) public view returns (uint256) {
        StakePosition memory pos = stakes[stakeId];
        if (pos.user == address(0) || pos.withdrawn) {
            return 0;
        }

        uint256 endTime = pos.startTime + pos.lockDuration;
        uint256 effectiveEnd = block.timestamp < endTime ? block.timestamp : endTime;

        if (effectiveEnd <= pos.startTime || pos.aprBps == 0) {
            return 0;
        }

        uint256 elapsed = effectiveEnd - pos.startTime;

        uint256 reward = (pos.amount * pos.aprBps * elapsed) / YEAR_IN_SECONDS / BASIS_POINTS;

        if (reward <= pos.claimedReward) {
            return 0;
        }

        return reward - pos.claimedReward;
    }

    // ===================================================
    // OWNER FUNCTIONS
    // ===================================================

    /**
     * @notice Starts a two-step ownership transfer for this staking contract.
     * @param newOwner The account that will be able to accept ownership.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OWNER_ZERO");
        require(newOwner != _owner, "OWNER_SAME");
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @notice Accepts ownership transfer for this staking contract.
     */
    function acceptOwnership() external {
        require(msg.sender == _pendingOwner, "NOT_PENDING_OWNER");
        address previousOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, _owner);
    }

    /**
     * @notice Cancels a pending ownership transfer.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        require(_pendingOwner != address(0), "NO_PENDING_TRANSFER");
        _pendingOwner = address(0);
        emit OwnershipTransferStarted(_owner, address(0));
    }

    /**
     * @notice Renounces staking ownership after the lock period.
     */
    function renounceOwnership() external onlyOwner {
        require(block.timestamp > launchTime + OWNERSHIP_LOCK_PERIOD, "OWNER_LOCKED");
        address previousOwner = _owner;
        _owner = address(0);
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }

    /// @notice Adds a new lock plan for future stakes.
    function addStakePlan(uint256 lockDuration, uint256 aprBps) external onlyOwner {
        require(lockDuration > 0, "DURATION_ZERO");
        require(aprBps <= 5000, "APR_TOO_HIGH"); // max 50% APR as a safety guideline
        uint256 planId = lockPlans.length;
        lockPlans.push(LockPlan({lockDuration: lockDuration, aprBps: aprBps, enabled: true}));
        emit PlanAdded(planId, lockDuration, aprBps);
    }

    /// @notice Updates an existing lock plan used for new stakes.
    function updateStakePlan(uint256 planId, uint256 lockDuration, uint256 aprBps, bool enabled)
        external
        onlyOwner
        validPlan(planId)
    {
        require(lockDuration > 0, "DURATION_ZERO");
        require(aprBps <= 5000, "APR_TOO_HIGH");
        lockPlans[planId].lockDuration = lockDuration;
        lockPlans[planId].aprBps = aprBps;
        lockPlans[planId].enabled = enabled;
        emit PlanUpdated(planId, lockDuration, aprBps, enabled);
    }

    /// @notice Sets or updates a human-readable name for a staking plan.
    /// @dev Names are optional metadata for frontends (e.g. "30 days", "90d 25% APR").
    function setStakePlanName(uint256 planId, string calldata name) external onlyOwner validPlan(planId) {
        require(bytes(name).length > 0, "NAME_EMPTY");
        stakePlanNames[planId] = name;
    }

    /// @notice Enables or disables new staking deposits globally.
    /// @dev Withdrawals and reward claims remain available while the token is not paused.
    function setDepositsEnabled(bool enabled) external onlyOwner {
        depositsEnabled = enabled;
        emit DepositsEnabledUpdated(enabled);
    }

    // ===================================================
    // USER FUNCTIONS
    // ===================================================

    /// @notice Stakes `amount` of NTE into the selected lock plan.
    /// @dev Tokens remain in the main NTE contract; this call locks `amount`
    ///      against the caller in NTE so they cannot be transferred.
    function stakeTokens(uint256 planId, uint256 amount)
        external
        nonReentrant
        notPaused
        validPlan(planId)
    {
        require(amount > 0, "AMOUNT_ZERO");
        require(depositsEnabled, "DEPOSITS_DISABLED");
        LockPlan memory plan = lockPlans[planId];
        require(plan.enabled, "PLAN_DISABLED");

        // Lock tokens in the main NTE contract instead of transferring them here
        stakingToken.lockFromStaking(msg.sender, amount);
        uint256 received = amount;

        uint256 stakeId = nextStakeId++;
        stakes[stakeId] = StakePosition({
            user: msg.sender,
            planId: planId,
            amount: received,
            startTime: block.timestamp,
            lockDuration: plan.lockDuration,
            aprBps: plan.aprBps,
            claimedReward: 0,
            withdrawn: false
        });

        userStakeIds[msg.sender].push(stakeId);

        totalStaked += received;

        // Emit the actual received amount, which can differ from `amount`
        // for fee-on-transfer or deflationary tokens.
        emit Staked(msg.sender, stakeId, planId, received);
    }

    /// @notice Claims only the rewards for a specific stake.
    /// @dev Principal remains locked until the lock duration has elapsed.
    function claimStakeRewards(uint256 stakeId) public nonReentrant notPaused {
        StakePosition storage pos = stakes[stakeId];
        require(pos.user == msg.sender, "NOT_OWNER_STAKE");
        require(!pos.withdrawn, "ALREADY_WITHDRAWN");

        uint256 reward = pendingReward(stakeId);
        if (reward == 0) {
            return;
        }

        pos.claimedReward += reward;
        require(stakingToken.transfer(msg.sender, reward), "REWARD_TRANSFER_FAIL");
        emit RewardClaimed(msg.sender, stakeId, reward);
    }

    /// @notice Claims rewards for all active stakes owned by the caller.
    function claimAllStakeRewards() external nonReentrant notPaused {
        uint256[] storage ids = userStakeIds[msg.sender];
        uint256 totalReward;

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 stakeId = ids[i];
            StakePosition storage pos = stakes[stakeId];
            if (pos.user != msg.sender || pos.withdrawn) {
                continue;
            }

            uint256 reward = pendingReward(stakeId);
            if (reward == 0) {
                continue;
            }

            pos.claimedReward += reward;
            totalReward += reward;
            emit RewardClaimed(msg.sender, stakeId, reward);
        }

        if (totalReward > 0) {
            require(stakingToken.transfer(msg.sender, totalReward), "REWARD_TRANSFER_FAIL");
        }
    }

    /// @notice Compounds pending rewards for a stake back into its principal amount.
    /// @dev No tokens leave the contract; rewards are added to the stake.
    function compoundStakeReward(uint256 stakeId) external nonReentrant notPaused {
        StakePosition storage pos = stakes[stakeId];
        require(pos.user == msg.sender, "NOT_OWNER_STAKE");
        require(!pos.withdrawn, "ALREADY_WITHDRAWN");
        uint256 lockEnd = pos.startTime + pos.lockDuration;

        uint256 reward = pendingReward(stakeId);
        if (reward == 0) {
            return;
        }

        pos.amount += reward;

        totalStaked += reward;

        // Send reward to user, then immediately lock it in the main token
        require(stakingToken.transfer(msg.sender, reward), "REWARD_TRANSFER_FAIL");
        stakingToken.lockFromStaking(msg.sender, reward);

        // Reset reward baseline to avoid retroactive accrual on compounded amount,
        // while preserving the original lock end time.
        pos.startTime = block.timestamp;
        if (lockEnd > block.timestamp) {
            pos.lockDuration = lockEnd - block.timestamp;
        } else {
            pos.lockDuration = 0;
        }
        pos.claimedReward = 0;

        emit RewardCompounded(msg.sender, stakeId, reward);
    }

    /// @notice Moves an existing stake into a different lock plan.
    /// @dev Pending rewards are first paid out, then the stake restarts under the new plan.
    function extendStakeLockPlan(uint256 stakeId, uint256 newPlanId)
        external
        nonReentrant
        notPaused
        validPlan(newPlanId)
    {
        StakePosition storage pos = stakes[stakeId];
        require(pos.user == msg.sender, "NOT_OWNER_STAKE");
        require(!pos.withdrawn, "ALREADY_WITHDRAWN");

        LockPlan memory targetPlan = lockPlans[newPlanId];
        require(targetPlan.enabled, "PLAN_DISABLED");
        uint256 currentLockEnd = pos.startTime + pos.lockDuration;
        uint256 remainingLock = currentLockEnd > block.timestamp ? currentLockEnd - block.timestamp : 0;
        require(targetPlan.lockDuration >= remainingLock, "LOCK_SHORTEN");

        uint256 reward = pendingReward(stakeId);
        if (reward > 0) {
            pos.claimedReward += reward;
            require(stakingToken.transfer(msg.sender, reward), "REWARD_TRANSFER_FAIL");
            emit RewardClaimed(msg.sender, stakeId, reward);
        }

        uint256 previousPlanId = pos.planId;
        pos.planId = newPlanId;
        pos.startTime = block.timestamp;
        pos.lockDuration = targetPlan.lockDuration;
        pos.aprBps = targetPlan.aprBps;
        pos.claimedReward = 0;

        emit StakePlanExtended(msg.sender, stakeId, previousPlanId, newPlanId);
    }

    /// @notice Withdraws principal and any remaining rewards after the lock period ends.
    function withdrawStakedTokens(uint256 stakeId) external nonReentrant notPaused {
        StakePosition storage pos = stakes[stakeId];
        require(pos.user == msg.sender, "NOT_OWNER_STAKE");
        require(!pos.withdrawn, "ALREADY_WITHDRAWN");

        require(block.timestamp >= pos.startTime + pos.lockDuration, "LOCK_ACTIVE");

        uint256 reward = pendingReward(stakeId);
        if (reward > 0) {
            pos.claimedReward += reward;
            require(stakingToken.transfer(msg.sender, reward), "REWARD_TRANSFER_FAIL");
            emit RewardClaimed(msg.sender, stakeId, reward);
        }

        uint256 principal = pos.amount;
        pos.withdrawn = true;
        pos.amount = 0;

        totalStaked -= principal;
        stakingToken.unlockFromStaking(msg.sender, principal);
        emit Withdrawn(msg.sender, stakeId, principal, reward);
    }

    /// @notice Withdraws only principal after lock expiry, forfeiting unclaimed rewards.
    function withdrawStakedPrincipalOnly(uint256 stakeId) external nonReentrant {
        StakePosition storage pos = stakes[stakeId];
        require(pos.user == msg.sender, "NOT_OWNER_STAKE");
        require(!pos.withdrawn, "ALREADY_WITHDRAWN");
        require(block.timestamp >= pos.startTime + pos.lockDuration, "LOCK_ACTIVE");

        uint256 principal = pos.amount;
        pos.withdrawn = true;
        pos.amount = 0;
        pos.claimedReward = 0;

        totalStaked -= principal;
        stakingToken.unlockFromStaking(msg.sender, principal);
        emit PrincipalWithdrawn(msg.sender, stakeId, principal);
    }

    /// @notice Performs an emergency exit by withdrawing principal before the lock ends.
    /// @dev All unclaimed rewards are forfeited.
    function emergencyWithdrawStakedTokens(uint256 stakeId) external nonReentrant {
        StakePosition storage pos = stakes[stakeId];
        require(pos.user == msg.sender, "NOT_OWNER_STAKE");
        require(!pos.withdrawn, "ALREADY_WITHDRAWN");

        uint256 principal = pos.amount;
        pos.withdrawn = true;
        pos.amount = 0;
        pos.claimedReward = 0;

        totalStaked -= principal;
        stakingToken.unlockFromStaking(msg.sender, principal);
        emit EmergencyWithdraw(msg.sender, stakeId, principal);
    }

    /**
     * @notice Emergency function to withdraw ERC20 tokens from this contract.
     * @dev Can withdraw any ERC20 held by this contract, including staking token rewards.
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        _withdrawToken(token, to, amount);
    }

    /// @notice Allows owner to recover non-staking ERC20 tokens sent accidentally.
    function recoverERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(stakingToken), "CANNOT_RECOVER_STAKING");
        _withdrawToken(token, to, amount);
    }

    /**
     * @notice Emergency function to withdraw BNB from this contract.
     * @dev Only possible after the ownership lock period.
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp > launchTime + OWNERSHIP_LOCK_PERIOD, "EMG_WAIT_30D");
        require(to != address(0), "TO_ZERO");
        require(amount <= address(this).balance, "INSUFFICIENT_BNB_BALANCE");
        (bool success, ) = to.call{value: amount}("");
        require(success, "EMG_BNB_FAIL");
        emit EmergencyBNBWithdraw(to, amount);
    }

    /// @dev Shared internal token-withdraw helper with non-standard ERC20 handling.
    function _withdrawToken(address token, address to, uint256 amount) internal {
        require(token != address(0), "TOKEN_ZERO");
        require(to != address(0), "TO_ZERO");
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        require(amount <= balance, "INSUFFICIENT_TOKEN_BALANCE");
        bytes memory payload = abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount);
        (bool success, bytes memory returndata) = token.call(payload);
        require(success, "TOKEN_TRANSFER_FAIL");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "TOKEN_TRANSFER_FAIL");
        }
        emit EmergencyTokenWithdraw(token, to, amount);
    }

    /// @notice Allows this contract to receive BNB.
    receive() external payable {
        emit BNBReceived(msg.sender, msg.value);
    }
}
