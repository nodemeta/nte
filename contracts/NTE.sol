// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NTE is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    // Mining state variables
    uint256 public miningReward;
    uint256 public miningDifficulty;
    uint256 public lastMinedBlock;
    uint256 public miningCooldownSeconds;
    mapping(address => uint256) public lastMiningAttempt;
    mapping(address => address) public miningBeneficiaries;

    // Staking state variables
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public lastStakeTime;
    uint256 public stakingRewardRate;

    // Tax-related state variables
    address public treasury;
    uint256 public taxPercent;

    // Token metadata controls
    string private _customName;
    string private _customSymbol;

    // Access control and safety mappings
    mapping(address => bool) public blacklist;
    mapping(address => bool) public taxExempt;
    mapping(address => uint256) public customCooldown;

    uint8 private _customDecimals;
    uint256 public stakingLockPeriod;

    // Events for admin actions
    event BlacklistUpdated(address account, bool value);
    event TaxExemptUpdated(address account, bool exempt);
    event CustomCooldownUpdated(address account, uint256 cooldownSeconds);
    event StakingLockPeriodUpdated(uint256 newLockPeriod);
    event NameSymbolUpdated(string newName, string newSymbol);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialize function to set initial parameters and mint initial supply
    function initialize(
        uint256 initialSupply,
        address initialOwner,
        uint256 _miningReward,
        uint256 _miningDifficulty,
        uint256 _stakingRewardRate,
        address _treasury,
        uint256 _taxPercent
    ) public initializer {
        __ERC20_init("Node Meta Energy", "NTE");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __Pausable_init();

        miningReward = _miningReward;
        miningDifficulty = _miningDifficulty;
        stakingRewardRate = _stakingRewardRate;
        treasury = _treasury;
        miningCooldownSeconds = 3600;
        taxPercent = _taxPercent;

        _customName = "Node Meta Energy";
        _customSymbol = "NTE";
        _customDecimals = 18;
        stakingLockPeriod = 0;

        _mint(initialOwner, initialSupply * 10 ** decimals());
    }

    // Return custom name for the token
    function name() public view override returns (string memory) {
        return _customName;
    }

    // Return custom symbol for the token
    function symbol() public view override returns (string memory) {
        return _customSymbol;
    }

    // Return custom decimals for the token
    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    // Allow owner to update the token name and symbol
    function setNameAndSymbol(string memory newName, string memory newSymbol) external onlyOwner {
        _customName = newName;
        _customSymbol = newSymbol;
        emit NameSymbolUpdated(newName, newSymbol);
    }

    // Allow owner to update decimals
    function setDecimals(uint8 newDecimals) external onlyOwner {
        _customDecimals = newDecimals;
    }

    // Return tokenURI metadata link
    function tokenURI() public pure returns (string memory) {
        return "";
    }

    // Set beneficiary address for mining rewards
    function setMiningBeneficiary(address beneficiary) external {
        miningBeneficiaries[msg.sender] = beneficiary;
    }

    // Mining function with cooldown and difficulty check
    function mine(uint256 nonce) external whenNotPaused {
        require(!blacklist[msg.sender], "Blacklisted");
        require(block.number > lastMinedBlock, "Wait for new block");

        uint256 cooldown = customCooldown[msg.sender] > 0 
            ? customCooldown[msg.sender] 
            : miningCooldownSeconds;

        require(block.timestamp > lastMiningAttempt[msg.sender] + cooldown, "Cooldown active");

        bytes32 hash = keccak256(abi.encodePacked(msg.sender, nonce, blockhash(block.number - 1)));
        require(uint256(hash) < miningDifficulty, "Mining failed");

        address rewardRecipient = miningBeneficiaries[msg.sender] != address(0) 
            ? miningBeneficiaries[msg.sender] 
            : msg.sender;

        _mint(rewardRecipient, miningReward * (10 ** decimals()));
        lastMinedBlock = block.number;
        lastMiningAttempt[msg.sender] = block.timestamp;
    }

    // Stake tokens and track staking time
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Cannot stake zero");
        require(!blacklist[msg.sender], "Blacklisted");

        _claimStakingRewards(msg.sender);
        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        lastStakeTime[msg.sender] = block.timestamp;
    }

    // Unstake tokens after lock period
    function unstake(uint256 amount) external whenNotPaused {
        require(!blacklist[msg.sender], "Blacklisted");
        require(stakedBalance[msg.sender] >= amount, "Not enough stake");
        require(block.timestamp > lastStakeTime[msg.sender] + stakingLockPeriod, "Locked");
        _claimStakingRewards(msg.sender);
        stakedBalance[msg.sender] -= amount;
        _transfer(address(this), msg.sender, amount);
    }

    // Calculate and mint staking rewards
    function _claimStakingRewards(address user) internal {
        uint256 staked = stakedBalance[user];
        if (staked == 0) return;

        uint256 duration = block.timestamp - lastStakeTime[user];
        uint256 reward = (staked * stakingRewardRate * duration) / (365 days * 100);
        if (reward > 0) {
            _mint(user, reward);
        }
        lastStakeTime[user] = block.timestamp;
    }

    // Transfer tokens with tax applied unless exempt or owner/contract involved
    function taxedTransfer(address to, uint256 amount) external whenNotPaused {
        address from = msg.sender;
        require(!blacklist[from] && !blacklist[to], "Blacklisted");

        if (
            from == owner() ||
            to == owner() ||
            from == address(this) ||
            to == address(this) ||
            taxExempt[from] || taxExempt[to]
        ) {
            _transfer(from, to, amount);
        } else {
            uint256 tax = (amount * taxPercent) / 100;
            uint256 afterTax = amount - tax;
            _transfer(from, treasury, tax);
            _transfer(from, to, afterTax);
        }
    }

    // Admin functions to update parameters
    function setMiningReward(uint256 newReward) external onlyOwner {
        miningReward = newReward;
    }

    function setMiningDifficulty(uint256 newDifficulty) external onlyOwner {
        miningDifficulty = newDifficulty;
    }

    function setStakingRewardRate(uint256 newRate) external onlyOwner {
        stakingRewardRate = newRate;
    }

    function setMiningCooldown(uint256 cooldownSeconds) external onlyOwner {
        miningCooldownSeconds = cooldownSeconds;
    }

    function setTaxPercent(uint256 newTaxPercent) external onlyOwner {
        taxPercent = newTaxPercent;
    }

    function setStakingLockPeriod(uint256 lockTime) external onlyOwner {
        stakingLockPeriod = lockTime;
        emit StakingLockPeriodUpdated(lockTime);
    }

    function setTaxExempt(address user, bool exempt) external onlyOwner {
        taxExempt[user] = exempt;
        emit TaxExemptUpdated(user, exempt);
    }

    function setCustomCooldown(address user, uint256 seconds_) external onlyOwner {
        customCooldown[user] = seconds_;
        emit CustomCooldownUpdated(user, seconds_);
    }

    function blacklistAddress(address user, bool value) external onlyOwner {
        blacklist[user] = value;
        emit BlacklistUpdated(user, value);
    }

    // Pause contract transfers and mining
    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    // Unpause contract
    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    // Mint tokens to address, blocks blacklisted recipients
    function mint(address to, uint256 amount) external onlyOwner {
        require(!blacklist[to], "Blacklisted");
        _mint(to, amount);
    }

    // Burn tokens from sender
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // Emergency withdraw tokens sent to contract
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    // Authorize UUPS upgrade - only owner can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
