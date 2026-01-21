// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal interface for NTE categorized transfers
interface INTECategorized {
    function TransactionFrom(
        address from,
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
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

    /**
     * @param _nte Address of the deployed NTE token.
     */
    constructor(address _nte) {
        require(_nte != address(0), "NTE_ZERO");
        nte = INTECategorized(_nte);
    }

    /// @notice Generic categorized transfer.
    function Transaction(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Payment" transfer.
    function Payment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Reward" transfer.
    function Reward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Bonus" transfer.
    function Bonus(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Payout" transfer.
    function Payout(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Deposit" transfer.
    function Deposit(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Withdrawal" transfer.
    function Withdrawal(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Purchase" transfer.
    function Purchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Refund" transfer.
    function Refund(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Fee" transfer.
    function Fee(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Subscription" transfer.
    function Subscription(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Sell" transfer.
    function Sell(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Gift" transfer.
    function Gift(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Others" transfer.
    function Others(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Airdrop" transfer.
    function Airdrop(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Mint"-related transfer (e.g. game/NFT mint fee).
    function Mint(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Royalty" payment.
    function Royalty(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Incentive" payment.
    function Incentive(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Penalty" deduction.
    function Penalty(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Cashback" transfer.
    function Cashback(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Swap" transfer.
    function Swap(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Bridge" transfer.
    function Bridge(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Escrow" transfer.
    function Escrow(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Loan" transfer.
    function Loan(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Repayment" transfer.
    function Repayment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Rent" transfer.
    function Rent(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Claim" transfer.
    function Claim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Level-Up Reward" transfer.
    function LevelUpReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Move-to-Earn Reward" transfer.
    function MoveToEarnReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Tournament Prize" transfer.
    function TournamentPrize(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Governance Voting Fee" transfer.
    function GovernanceVotingFee(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Card Payment" transfer.
    function CardPayment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Salary" payment.
    function Salary(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Staking Reward" transfer.
    function StakingReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Farming Reward" transfer.
    function FarmingReward(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Lottery Prize" transfer.
    function LotteryPrize(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Charity" transfer.
    function Charity(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Donation" transfer.
    function Donation(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Tip" transfer.
    function Tip(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Partner Payment" transfer.
    function PartnerPayment(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Referral Bonus Claim" transfer.
    function ReferralBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Core Node Purchase" transfer.
    function CoreNodePurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Elite Node Purchase" transfer.
    function EliteNodePurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Core Node Bonus Claim" transfer.
    function CoreNodeBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Elite Node Bonus Claim" transfer.
    function EliteNodeBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Staking Purchase" transfer.
    function StakingPurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Staking Bonus Claim" transfer.
    function StakingBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Meta Pulse Purchase" transfer.
    function MetaPulsePurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "Meta Pulse Bonus Claim" transfer.
    function MetaPulseBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "DBE Purchase" transfer.
    function DBEPurchase(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }

    /// @notice Alias for a categorized "DBE Bonus Claim" transfer.
    function DBEBonusClaim(
        address to,
        uint256 amount,
        uint8 category,
        bytes calldata signature,
        uint256 nonce,
        string calldata txReference,
        string calldata memo
    ) external returns (bool) {
        return nte.TransactionFrom(msg.sender, to, amount, category, signature, nonce, txReference, memo);
    }
}
