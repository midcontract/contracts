// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Enums {
    /// @notice Enumerates the different configurations of fee responsibilities.
    enum FeeConfig {
        CLIENT_COVERS_ALL, // Client pays both coverage and claim fees (total 8%)
        CLIENT_COVERS_ONLY, // Client pays only the coverage fee (3%), contractor responsible for the claim fee (5%)
        CONTRACTOR_COVERS_CLAIM, // Contractor pays the claim fee (5%), no coverage fee applied
        NO_FEES // No fees applied (0%)
    }
}
