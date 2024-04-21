// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./libs/Owned.sol";

contract EscrowFeeManager is Owned {
    error Escrow__FeeTooHigh();
    error Escrow__InvalidFeeConfig();

    /// @notice The basis points used for calculating fees and percentages.
    uint256 public constant MAX_BPS = 100_00; // 100%

    uint256 public feeCoverage;
    uint256 public feeClaim;

    enum FeeConfig {
        FULL, 
        ONLY_CLIENT,
        ONLY_CONTRACTOR,
        FREE
    }

    constructor(uint256 _feeCoverage, uint256 _feeClaim) Owned(msg.sender) {
        if (_feeCoverage > MAX_BPS || _feeClaim > MAX_BPS) revert Escrow__FeeTooHigh();

        feeCoverage = _feeCoverage;
        feeClaim = _feeClaim;
    }

    // Coverage fee:
    // formula: Contract_budget * (1 + coverage_fee)
    // 3% if not payed for the freelancer
    // 8% if payed for the freelancer

    function computeCoverageFee(uint256 _amount, uint256 _feeConfig) external returns (uint256) {
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            return (_amount * (feeCoverage + feeClaim)) / MAX_BPS;
        } else if (_feeConfig == uint256(FeeConfig.ONLY_CLIENT)) {
            return ((_amount * feeCoverage) / MAX_BPS);
        } else if (_feeConfig == uint256(FeeConfig.ONLY_CONTRACTOR)) {
            return ((_amount * feeClaim) / MAX_BPS);
        } else if (_feeConfig == uint256(FeeConfig.FREE)) {
            return 0;
        } else {
            revert Escrow__InvalidFeeConfig();
        }
    }

    // Claim fee:
    // formula: Contract_budget * (1 - claim_fee)
    // 5% if not payed by the client
    // 0% if payed by the client

    function computeClaimFee(uint256 _amount, FeeConfig _feeConfig) external returns (uint256) {}

    function setFeeConfig(uint256 _feeCoverage, uint256 _feeClaim) external onlyOwner {}
}
