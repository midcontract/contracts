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

    /// @notice Enumerates the different statuses for a contract or transaction.
    enum Status {
        PENDING, // Contract or transaction is pending
        SUBMITTED, // Contract or transaction has been submitted but not yet approved
        APPROVED // Contract or transaction has been approved
    }
}
