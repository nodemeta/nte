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

    /**
     * @notice Deploys a new multi-plan staking contract for NTE.
     * @dev Initializes with NTE token address, sets initial owner to NTE token owner,
     *      and records launch time for ownership lock period. Validates token is a contract.
     * @param _stakingToken Address of the NTE token used for staking.
     * @custom:example constructor(0x123...NTE)
     * @custom:security Validates token is non-zero, is a contract, and has an owner.
     * @custom:reverts "TOKEN_ZERO" if token is zero address.
     * @custom:reverts "TOKEN_NOT_CONTRACT" if token is not a contract.
     * @custom:reverts "OWNER_ZERO" if NTE token owner is zero address.
     * @custom:usecase Deploy staking contract, then add lock plans via addStakePlan().
     */
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

    /**
     * @notice Returns the total number of configured lock plans.
     * @dev Plans are indexed from 0 to (count - 1). New plans are appended via addStakePlan().
     * @return The number of staking plans available.
     * @custom:example getPlansCount() returns 3 if plans 0, 1, 2 exist
     * @custom:usecase Check how many plans exist before calling getAllStakePlans() or validating planId.
     */
    function getPlansCount() external view returns (uint256) {
        return lockPlans.length;
    }

    /**
     * @notice Returns the current owner of the staking contract.
     * @dev Owner can modify plans, set deposit status, and perform emergency operations.
     * @return The address of the current owner.
     * @custom:example owner() returns 0x123...
     * @custom:usecase Verify ownership before calling onlyOwner functions or for UI display.
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice Returns the pending owner in a two-step ownership transfer.
     * @dev Returns zero address if no transfer is pending. Pending owner can call acceptOwnership().
     * @return The address of the pending owner, or zero if none.
     * @custom:example pendingOwner() returns 0x456... if transfer initiated but not accepted
     * @custom:usecase Check if an ownership transfer is pending before accepting or canceling.
     */
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /**
     * @notice Returns all stake IDs owned by a specific user.
     * @dev Array includes both active and withdrawn stakes. Use getUserStakeInfo() for full details.
     *      IDs are assigned sequentially starting from 1; array preserves creation order.
     * @param user The address to query stake IDs for.
     * @return Array of stake IDs owned by the user.
     * @custom:example getUserStakeIds(userAddress) returns [1, 3, 7]
     * @custom:usecase Iterate through user's stakes or check how many stakes a user has created.
     */
    function getUserStakeIds(address user) external view returns (uint256[] memory) {
        return userStakeIds[user];
    }

    /**
     * @notice Returns the current NTE balance held by this contract for paying rewards.
     * @dev Does not include principal (principal is locked in main NTE contract).
     *      Owner should monitor this balance to ensure sufficient rewards for stakers.
     * @return The NTE token balance available for reward payouts.
     * @custom:example rewardPoolBalance() returns 100000e18 // 100k NTE available
     * @custom:usecase Monitor reward pool liquidity before adding new plans or to fund contract.
     */
    function rewardPoolBalance() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    /**
     * @notice Returns all staking plans with their configuration and optional names.
     * @dev Includes planId, lockDuration, aprBps, enabled status, and name for each plan.
     *      Name is empty string if setStakePlanName() was never called for that plan.
     * @return Array of LockPlanInfo structs containing complete plan data.
     * @custom:example getAllStakePlans() returns plans with 30d/10%, 90d/25%, 180d/40% configs
     * @custom:usecase Display all available staking options in UI with durations, APRs, and names.
     */
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
     * @notice Returns all stake positions owned by a user with complete details.
     * @dev Returns StakePosition structs including withdrawn stakes. Does not include plan names or pending rewards.
     *      For enriched data with plan names and current rewards, use getUserStakeInfo().
     * @param user The address to query stake positions for.
     * @return Array of StakePosition structs for all user's stakes.
     * @custom:example getUserPositions(userAddress) returns [{user, planId, amount, startTime...}, ...]
     * @custom:usecase Backend analysis or raw stake data access without UI metadata.
     */
    function getUserPositions(address user) external view returns (StakePosition[] memory) {
        uint256[] storage ids = userStakeIds[user];
        StakePosition[] memory positions = new StakePosition[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            positions[i] = stakes[ids[i]];
        }
        return positions;
    }

    /**
     * @notice Returns the total principal currently staked by a user across all active stakes.
     * @dev Only counts non-withdrawn stakes; includes compounded rewards in the amount.
     *      Excludes withdrawn stakes even if they had balance before withdrawal.
     * @param user The address to calculate total staked for.
     * @return Total NTE amount currently locked for the user across all active stakes.
     * @custom:example userTotalStaked(userAddress) returns 5000e18 // 5000 NTE locked
     * @custom:usecase Display user's total locked balance or calculate portfolio allocation.
     */
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

    /**
     * @notice Returns the total unclaimed rewards across all active stakes owned by a user.
     * @dev Sums pendingReward() for each active stake; excludes withdrawn stakes.
     *      Rewards stop accruing at lock end; claimed rewards are deducted automatically.
     * @param user The address to calculate total pending rewards for.
     * @return Total NTE rewards claimable by the user right now.
     * @custom:example userTotalPendingRewards(userAddress) returns 250e18 // 250 NTE claimable
     * @custom:usecase Display total earnings in UI or calculate claimAllStakeRewards() outcome.
     */
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

    /**
     * @notice Returns enriched stake information for a user with plan names and pending rewards.
     * @dev Combines stake data with plan names from stakePlanNames mapping and live pendingReward calculations.
     *      Most comprehensive view function for displaying user stakes in UI.
     * @param user The address to query enriched stake info for.
     * @return Array of UserStakeInfo structs with stakeId, planId, planName, amount, timestamps, rewards, etc.
     * @custom:example getUserStakeInfo(userAddress) returns detailed array with all stake metadata
     * @custom:usecase Primary function for displaying user's staking dashboard with all details.
     */
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

    /**
     * @notice Returns the unclaimed reward for a specific stake.
     * @dev Calculates rewards from stake start to min(now, lockEnd) based on APR and amount.
     *      Subtracts already claimed rewards. Returns 0 for withdrawn stakes or stakes with no user.
     *      Formula: (amount * aprBps * elapsed) / YEAR_IN_SECONDS / BASIS_POINTS - claimedReward
     * @param stakeId The stake position ID to calculate pending rewards for.
     * @return The NTE reward amount claimable right now for this stake.
     * @custom:example pendingReward(1) returns 50e18 // 50 NTE reward for stake #1
     * @custom:usecase Check rewards before claiming, compounding, or withdrawing to show users.
     */
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
     * @notice Initiates a two-step ownership transfer for this staking contract.
     * @dev New owner must call acceptOwnership() to complete the transfer.
     *      Current owner can cancel via cancelOwnershipTransfer() before acceptance.
     * @param newOwner The account that will be able to accept ownership.
     * @custom:example transferOwnership(0x456...newOwner)
     * @custom:security Prevents transfers to zero address or current owner.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "OWNER_ZERO" if newOwner is the zero address.
     * @custom:reverts "OWNER_SAME" if newOwner is already the current owner.
     * @custom:usecase Transfer staking contract ownership to new admin or multisig.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OWNER_ZERO");
        require(newOwner != _owner, "OWNER_SAME");
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @notice Accepts ownership transfer for this staking contract.
     * @dev Only the pending owner can complete the transfer.
     * @custom:example acceptOwnership() // called by pending owner
     * @custom:security Only callable by address set in transferOwnership().
     * @custom:reverts "NOT_PENDING_OWNER" if caller is not the pending owner.
     * @custom:usecase Complete ownership transfer after previous owner initiated it.
     */
    function acceptOwnership() external {
        require(msg.sender == _pendingOwner, "NOT_PENDING_OWNER");
        address previousOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, _owner);
    }

    /**
     * @notice Cancels a pending ownership transfer for this staking contract.
     * @dev Resets the pending owner to zero, preventing them from accepting ownership.
     *      Only callable by the current owner before the new owner accepts.
     * @custom:example cancelOwnershipTransfer() // abort transfer
     * @custom:security Only current owner can cancel; reverts if no pending transfer exists.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "NO_PENDING_TRANSFER" if no ownership transfer is pending.
     * @custom:usecase Abort a staking ownership transfer initiated in error or if new owner is compromised.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        require(_pendingOwner != address(0), "NO_PENDING_TRANSFER");
        _pendingOwner = address(0);
        emit OwnershipTransferStarted(_owner, address(0));
    }

    /**
     * @notice Renounces staking ownership permanently after the 30-day lock period.
     * @dev Sets ownership to zero address, making the contract immutable.
     *      Only possible after OWNERSHIP_LOCK_PERIOD (30 days) from launchTime.
     * @custom:example renounceOwnership() // after 30 days
     * @custom:security Irreversible action; contract becomes immutable with no admin.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "OWNER_LOCKED" if 30-day lock period has not elapsed.
     * @custom:usecase Decentralize staking by removing admin control after initial configuration.
     */
    function renounceOwnership() external onlyOwner {
        require(block.timestamp > launchTime + OWNERSHIP_LOCK_PERIOD, "OWNER_LOCKED");
        address previousOwner = _owner;
        _owner = address(0);
        _pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }

    /**
     * @notice Adds a new staking lock plan with specified duration and APR.
     * @dev Creates an enabled plan with auto-incremented planId. Max APR is 50% (5000 bps).
     *      Existing stakes are unaffected; new plan only applies to future stakes.
     * @param lockDuration Lock duration in seconds (e.g., 30 days = 2592000).
     * @param aprBps Annual percentage rate in basis points (e.g., 1000 = 10% APR).
     * @custom:example addStakePlan(2592000, 1000) // 30 days, 10% APR
     * @custom:security Validates non-zero duration and max 50% APR to prevent misconfiguration.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "DURATION_ZERO" if lockDuration is zero.
     * @custom:reverts "APR_TOO_HIGH" if aprBps exceeds 5000 (50%).
     * @custom:usecase Add 30-day, 90-day, 180-day plans with varying APRs for stakers.
     */
    function addStakePlan(uint256 lockDuration, uint256 aprBps) external onlyOwner {
        require(lockDuration > 0, "DURATION_ZERO");
        require(aprBps <= 5000, "APR_TOO_HIGH"); // max 50% APR as a safety guideline
        uint256 planId = lockPlans.length;
        lockPlans.push(LockPlan({lockDuration: lockDuration, aprBps: aprBps, enabled: true}));
        emit PlanAdded(planId, lockDuration, aprBps);
    }

    /**
     * @notice Updates an existing staking plan's duration, APR, and enabled status.
     * @dev Existing stakes with this planId are unaffected; changes apply only to new stakes.
     *      Can disable a plan to prevent new stakes while allowing existing stakes to mature.
     * @param planId The plan index to update (0-based).
     * @param lockDuration New lock duration in seconds.
     * @param aprBps New annual percentage rate in basis points.
     * @param enabled Whether the plan is available for new stakes.
     * @custom:example updateStakePlan(0, 2592000, 1200, true) // update plan 0 to 12% APR
     * @custom:security Validates duration and APR; existing stakes unaffected for fairness.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "INVALID_PLAN" if planId doesn't exist.
     * @custom:reverts "DURATION_ZERO" if lockDuration is zero.
     * @custom:reverts "APR_TOO_HIGH" if aprBps exceeds 5000 (50%).
     * @custom:usecase Adjust plan parameters based on market conditions or disable underused plans.
     */
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

    /**
     * @notice Sets or updates a human-readable name for a staking plan.
     * @dev Names are optional UI metadata (e.g., "30 Days", "90d 25% APR").
     *      Returned in getAllStakePlans() and getUserStakeInfo() view functions.
     * @param planId The plan index to name (0-based).
     * @param name The display name for frontends and dashboards.
     * @custom:example setStakePlanName(0, "30 Days - 10% APR")
     * @custom:security Validates non-empty name; purely cosmetic, no contract logic affected.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "INVALID_PLAN" if planId doesn't exist.
     * @custom:reverts "NAME_EMPTY" if name is an empty string.
     * @custom:usecase Provide user-friendly plan names in dApp UI for better UX.
     */
    function setStakePlanName(uint256 planId, string calldata name) external onlyOwner validPlan(planId) {
        require(bytes(name).length > 0, "NAME_EMPTY");
        stakePlanNames[planId] = name;
    }

    /**
     * @notice Enables or disables new staking deposits globally.
     * @dev Withdrawals and reward claims remain available regardless of this setting.
     *      Use to temporarily pause new stakes during maintenance or migrations.
     * @param enabled True to allow new stakes, false to block them.
     * @custom:example setDepositsEnabled(false) // pause new deposits
     * @custom:security Does not affect existing stakes; they continue earning and can be withdrawn.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:usecase Pause deposits during contract upgrade or when reward pool is insufficient.
     */
    function setDepositsEnabled(bool enabled) external onlyOwner {
        depositsEnabled = enabled;
        emit DepositsEnabledUpdated(enabled);
    }

    // ===================================================
    // USER FUNCTIONS
    // ===================================================

    /**
     * @notice Stakes `amount` of NTE into the selected lock plan.
     * @dev Tokens remain in the main NTE contract; this call locks `amount`
     *      against the caller in NTE so they cannot be transferred. Rewards are paid from
     *      this staking contract's NTE balance.
     * @param planId The staking plan ID to use (0-based index).
     * @param amount The number of NTE tokens to stake.
     * @custom:example stakeTokens(0, 1000e18) // stake 1000 NTE in plan 0
     * @custom:security Validates plan exists, is enabled, amount is non-zero, and deposits are enabled.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_PAUSED" if NTE token is paused.
     * @custom:reverts "INVALID_PLAN" if planId doesn't exist.
     * @custom:reverts "AMOUNT_ZERO" if amount is zero.
     * @custom:reverts "DEPOSITS_DISABLED" if deposits are globally disabled.
     * @custom:reverts "PLAN_DISABLED" if the selected plan is disabled.
     * @custom:usecase Stake NTE to earn rewards; tokens  locked in main NTE contract.
     */
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

    /**
     * @notice Claims accumulated rewards for a specific stake without withdrawing principal.
     * @dev Principal remains locked until the lock period ends. Transfers NTE rewards to caller.
     *      If no rewards are pending, function returns without reverting.
     * @param stakeId The stake position ID to claim rewards from.
     * @custom:example claimStakeRewards(1) // claim rewards from stake #1
     * @custom:security Only stake owner can claim; validates stake exists and is not withdrawn.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_PAUSED" if NTE token is paused.
     * @custom:reverts "NOT_OWNER_STAKE" if caller is not the stake owner.
     * @custom:reverts "ALREADY_WITHDRAWN" if stake has been withdrawn.
     * @custom:reverts "REWARD_TRANSFER_FAIL" if reward transfer fails.
     * @custom:usecase Claim rewards periodically while keeping principal staked for compounding benefits.
     */
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

    /**
     * @notice Claims accumulated rewards from all active stakes owned by the caller.
     * @dev Iterates through caller's stake IDs, claims all pending rewards in a single transaction.
     *      Skips withdrawn stakes and stakes with zero rewards. Gas-efficient batch claim.
     * @custom:example claimAllStakeRewards() // claim from all stakes in one tx
     * @custom:security Only claims from caller's own stakes; validates each stake individually.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_PAUSED" if NTE token is paused.
     * @custom:reverts "REWARD_TRANSFER_FAIL" if total reward transfer fails.
     * @custom:usecase Harvest rewards from multiple stake positions efficiently without multi-call overhead.
     */
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

    /**
     * @notice Compounds pending rewards for a stake by adding them to the principal.
     * @dev Transfers rewards to user, immediately locks them back in main NTE contract, then adds to stake amount.
     *      Resets reward accrual start time to now, preserves original lock end time.
     * @param stakeId The stake position ID to compound rewards for.
     * @custom:example compoundStakeReward(1) // compound stake #1 rewards
     * @custom:security Locks rewards in NTE to maintain total staked accuracy; preserves lock end time.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_PAUSED" if NTE token is paused.
     * @custom:reverts "NOT_OWNER_STAKE" if caller is not the stake owner.
     * @custom:reverts "ALREADY_WITHDRAWN" if stake has been withdrawn.
     * @custom:reverts "REWARD_TRANSFER_FAIL" if reward transfer fails.
     * @custom:usecase Maximize returns via compound interest without creating new stakes.
     */
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

    /**
     * @notice Moves an existing stake into a different lock plan.
     * @dev Claims and pays pending rewards first, then restarts stake under new plan.
     *      Prevents shortening lock duration; new plan must have equal or longer duration than remaining lock.
     * @param stakeId The stake position ID to extend.
     * @param newPlanId The target plan ID to move the stake into.
     * @custom:example extendStakeLockPlan(1, 2) // move stake #1 to plan #2
     * @custom:security Validates new plan enabled, prevents lock shortening, claims rewards before extension.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_PAUSED" if NTE token is paused.
     * @custom:reverts "INVALID_PLAN" if newPlanId doesn't exist.
     * @custom:reverts "NOT_OWNER_STAKE" if caller is not the stake owner.
     * @custom:reverts "ALREADY_WITHDRAWN" if stake has been withdrawn.
     * @custom:reverts "PLAN_DISABLED" if new plan is disabled.
     * @custom:reverts "LOCK_SHORTEN" if new plan duration is less than remaining lock time.
     * @custom:reverts "REWARD_TRANSFER_FAIL" if reward claim fails.
     * @custom:usecase Extend a 30-day stake to 90-day plan for higher APR without withdrawing.
     */
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

    /**
     * @notice Withdraws principal and remaining rewards after the lock period ends.
     * @dev Claims any pending rewards, then unlocks principal in main NTE contract.
     *      Only callable after lock duration has elapsed. Marks stake as withdrawn.
     * @param stakeId The stake position ID to withdraw from.
     * @custom:example withdrawStakedTokens(1) // full withdrawal after lock ends
     * @custom:security Validates lock period ended; unlocks tokens in NTE, marks stake withdrawn.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_PAUSED" if NTE token is paused.
     * @custom:reverts "NOT_OWNER_STAKE" if caller is not the stake owner.
     * @custom:reverts "ALREADY_WITHDRAWN" if stake has been withdrawn.
     * @custom:reverts "LOCK_ACTIVE" if lock duration has not elapsed.
     * @custom:reverts "REWARD_TRANSFER_FAIL" if reward transfer fails.
     * @custom:usecase Standard withdrawal after 30/90 days; collect principal + all earned rewards.
     */
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

    /**
     * @notice Withdraws only principal after lock expiry, forfeiting all unclaimed rewards.
     * @dev No token pause check; allows faster exit without reward claim processing.
     *      Unlocks principal in main NTE contract. Rewards are forfeited permanently.
     * @param stakeId The stake position ID to withdraw principal from.
     * @custom:example withdrawStakedPrincipalOnly(1) // exit fast, forfeit rewards
     * @custom:security Validates lock ended; forfeits all rewards as tradeoff for no-pause requirement.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "NOT_OWNER_STAKE" if caller is not the stake owner.
     * @custom:reverts "ALREADY_WITHDRAWN" if stake has been withdrawn.
     * @custom:reverts "LOCK_ACTIVE" if lock duration has not elapsed.
     * @custom:usecase Emergency exit when NTE token is paused or gas-sensitive fast withdrawal needed.
     */
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

    /**
     * @notice Performs an emergency exit by withdrawing principal before the lock ends.
     * @dev No pause check; allows immediate exit even during paused state.
     *      All unclaimed rewards are forfeited. Principal is unlocked in main NTE contract.
     * @param stakeId The stake position ID to emergency withdraw from.
     * @custom:example emergencyWithdrawStakedTokens(1) // exit early, forfeit all rewards
     * @custom:security No lock duration check; allows bypass of time lock in true emergencies.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "NOT_OWNER_STAKE" if caller is not the stake owner.
     * @custom:reverts "ALREADY_WITHDRAWN" if stake has been withdrawn.
     * @custom:usecase Critical exit during exploit, contract issue, or user liquidity emergency.
     */
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
     * @notice Emergency function to withdraw any ERC20 tokens from this contract.
     * @dev Can withdraw any ERC20, including staking token reward pool.
     *      Uses low-level call to handle non-standard ERC20 implementations.
     * @param token The ERC20 token address to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     * @param amount The amount of tokens to withdraw.
     * @custom:example emergencyWithdrawToken(0x123...DAI, owner, 1000e18)
     * @custom:security Only owner; validates token/to addresses, sufficient balance, transfer success.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "TOKEN_ZERO" if token is zero address.
     * @custom:reverts "TO_ZERO" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_TOKEN_BALANCE" if contract lacks sufficient balance.
     * @custom:reverts "TOKEN_TRANSFER_FAIL" if transfer call fails or returns false.
     * @custom:usecase Recover mistakenly sent tokens or withdraw reward pool in critical scenarios.
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        _withdrawToken(token, to, amount);
    }

    /**
     * @notice Allows owner to recover non-staking ERC20 tokens sent accidentally.
     * @dev Prevents withdrawal of the staking token (NTE) to protect reward pool integrity.
     *      Uses same low-level call logic as emergencyWithdrawToken for compatibility.
     * @param token The ERC20 token address to recover.
     * @param to The recipient address for the recovered tokens.
     * @param amount The amount of tokens to recover.
     * @custom:example recoverERC20(0x123...USDT, owner, 500e6) // recover accidental USDT
     * @custom:security Blocks staking token withdrawal; only allows mistakenly sent third-party tokens.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "CANNOT_RECOVER_STAKING" if token is the staking token (NTE).
     * @custom:reverts "TOKEN_ZERO" if token is zero address.
     * @custom:reverts "TO_ZERO" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_TOKEN_BALANCE" if contract lacks sufficient balance.
     * @custom:reverts "TOKEN_TRANSFER_FAIL" if transfer call fails or returns false.
     * @custom:usecase Rescue USDT, DAI, or other tokens accidentally sent to staking contract.
     */
    function recoverERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(stakingToken), "CANNOT_RECOVER_STAKING");
        _withdrawToken(token, to, amount);
    }

    /**
     * @notice Emergency function to withdraw BNB from this staking contract.
     * @dev Only possible after 30-day ownership lock period to prevent early misuse.
     *      Uses low-level call to transfer BNB; validates balance and success.
     * @param to The recipient address for the withdrawn BNB.
     * @param amount The amount of BNB (in wei) to withdraw.
     * @custom:example emergencyWithdrawBNB(payable(owner), 1 ether)
     * @custom:security 30-day delay prevents immediate theft after deployment; validates recipient and balance.
     * @custom:reverts "NOT_OWNER" if caller is not the owner.
     * @custom:reverts "REENTRANT" on reentrant call attempts.
     * @custom:reverts "EMG_WAIT_30D" if 30 days have not elapsed since launch.
     * @custom:reverts "TO_ZERO" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_BNB_BALANCE" if contract lacks sufficient BNB.
     * @custom:reverts "EMG_BNB_FAIL" if BNB transfer call fails.
     * @custom:usecase Recover accidental BNB sent to contract or extract BNB from unexpected sources.
     */
    function emergencyWithdrawBNB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp > launchTime + OWNERSHIP_LOCK_PERIOD, "EMG_WAIT_30D");
        require(to != address(0), "TO_ZERO");
        require(amount <= address(this).balance, "INSUFFICIENT_BNB_BALANCE");
        (bool success, ) = to.call{value: amount}("");
        require(success, "EMG_BNB_FAIL");
        emit EmergencyBNBWithdraw(to, amount);
    }

    /**
     * @dev Shared internal token-withdraw helper with non-standard ERC20 handling.
     *      Uses low-level call to support tokens that don't return bool (e.g., USDT).
     *      Validates addresses, balance, and both call success and return value if present.
     *      Used by emergencyWithdrawToken() and recoverERC20().
     * @param token The ERC20 token address to withdraw.
     * @param to The recipient address for the tokens.
     * @param amount The amount of tokens to transfer.
     * @custom:security Validates non-zero addresses, sufficient balance, and transfer success.
     * @custom:reverts "TOKEN_ZERO" if token is zero address.
     * @custom:reverts "TO_ZERO" if recipient is zero address.
     * @custom:reverts "INSUFFICIENT_TOKEN_BALANCE" if contract balance is less than amount.
     * @custom:reverts "TOKEN_TRANSFER_FAIL" if low-level call fails or returns false.
     */
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

    /**
     * @notice Allows this contract to receive BNB via direct transfers or from liquidations.
     * @dev Emits BNBReceived event for tracking incoming BNB. Owner can withdraw via emergencyWithdrawBNB().
     *      BNB is not used for staking operations but can be recovered by owner after 30 days.
     * @custom:example Send BNB: address(stakingContract).transfer(1 ether)
     * @custom:usecase Accept accidental BNB transfers or BNB from other contracts for later recovery.
     */
    receive() external payable {
        emit BNBReceived(msg.sender, msg.value);
    }
}
