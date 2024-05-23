// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
        PENDING,            // Initial state, awaiting actions
        SUBMITTED,          // Work submitted by the contractor but not yet approved
        APPROVED,           // Work has been approved
        COMPLETED,          // The final claim has been done
        RETURN_REQUESTED,   // Client has requested a return of funds
        DISPUTED,           // A dispute has been raised following a denied return request
        RESOLVED,           // The dispute has been resolved
        REFUND_APPROVED,    // Refund has been approved, funds can be withdrawn
        CANCELLED           // Contract has been cancelled after a refund or resolution
    }

    /// @notice Enumerates the potential outcomes of a dispute resolution.
    /// @dev Describes who the winner of a dispute can be in various contexts, including partial resolutions.
    enum Winner {
        Client,  // Indicates the dispute was resolved in favor of the client
        Contractor, // Indicates the dispute was resolved in favor of the contractor
        Split // Indicates the dispute resolution benefits both parties
    }
}
