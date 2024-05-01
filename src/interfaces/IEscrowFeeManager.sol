  // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEscrowFeeManager {
    error EscrowFeeManager__FeeTooHigh();
    error EscrowFeeManager__InvalidFeeConfig();
    error EscrowFeeManager__ZeroAddressProvided();

    event DefaultFeesSet(uint256 coverage, uint256 claim);
    event SpecialFeesSet(address user, uint256 coverage, uint256 claim);
}