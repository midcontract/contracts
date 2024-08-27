// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Enumerations for Fee Configurations and Status
library Enums {
    /// @notice Enumerates the different configurations of fee responsibilities.
    enum FeeConfig {
        CLIENT_COVERS_ALL, // Client pays both coverage and claim fees (total 8%)
        CLIENT_COVERS_ONLY, // Client pays only the coverage fee (3%), contractor responsible for the claim fee (5%)
        CONTRACTOR_COVERS_CLAIM, // Contractor pays the claim fee (5%), no coverage fee applied
        NO_FEES // No fees applied (0%)

    }

    /// @notice Enumerates the different statuses for a contract.
    enum Status {
        ACTIVE, // The contract is active and ongoing
        SUBMITTED, // Work submitted by the contractor but not yet approved
        APPROVED, // Work has been approved
        COMPLETED, // The final claim has been done
        RETURN_REQUESTED, // Client has requested a return of funds
        DISPUTED, // A dispute has been raised following a denied return request
        RESOLVED, // The dispute has been resolved
        REFUND_APPROVED, // Refund has been approved, funds can be withdrawn
        CANCELED // Contract has been cancelled after a refund or resolution

    }

    /// @notice Enumerates the potential outcomes of a dispute resolution.
    /// @dev Describes who the winner of a dispute can be in various contexts, including partial resolutions.
    enum Winner {
        NONE, // Indicates that no resolution has been made yet or the dispute is unresolved
        CLIENT, // Indicates the dispute was resolved in favor of the client
        CONTRACTOR, // Indicates the dispute was resolved in favor of the contractor
        SPLIT // Indicates the dispute resolution benefits both parties

    }

    /// @notice Defines the types of escrow contracts that can be created.
    /// @dev Used in the factory contract to specify which type of escrow contract to deploy.
    enum EscrowType {
        FIXED_PRICE, // Represents a fixed price contract where the payment is made as a lump sum.
        MILESTONE, // Represents a contract where payment is divided into milestones, each payable upon completion.
        HOURLY, // Represents a contract where payment is made based on hourly rates and actual time worked.
        INVALID // Used as a sentinel value or error state where the escrow type is not defined or out of valid range.
    }

    /// @notice Specifies the types of refills possible within an escrow contract.
    /// @dev Used to determine whether a refill operation is targeting the overall contract prepayment or a specific week's payment within the contract.
    enum RefillType {
        PREPAYMENT, // Indicates a refill to the contract's general prepayment pool, which can be used to cover future claims.
        WEEK_PAYMENT // Indicates a refill targeted at a specific week's deposit amount within the contract, typically to fulfill or increase the amount claimable for that week.

    }

    /// @notice Enumerates the types of accounts that can be subject to recovery processes in the escrow system.
    /// @dev Used to specify the type of account (client or contractor) that needs recovery in case of access issues.
    enum AccountTypeRecovery {
        CLIENT, // Represents a client account, typically the party funding the escrow.
        CONTRACTOR // Represents a contractor account, typically the party performing services or work.

    }
}
