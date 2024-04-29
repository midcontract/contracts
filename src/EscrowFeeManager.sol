// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowFeeManager} from "./interfaces/IEscrowFeeManager.sol";
import {Owned} from "./libs/Owned.sol";

contract EscrowFeeManager is IEscrowFeeManager, Owned {
    /// @notice The basis points used for calculating fees and percentages.
    uint256 public constant MAX_BPS = 100_00; // 100%

    uint256 public defaultCoverageFee;
    uint256 public defaultClaimFee;

    mapping(address client => uint256 coverageFee) public specialCoverageFee;
    mapping(address contractor => uint256 claimFee) public specialClaimFee; 

    enum FeeConfig {
        FULL, 
        ONLY_CLIENT,
        ONLY_CONTRACTOR,
        FREE
    }

    constructor(uint256 _defaultCoverageFee, uint256 _defaultClaimFee) Owned(msg.sender) {
        if (_defaultCoverageFee > MAX_BPS || _defaultClaimFee > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();

        defaultCoverageFee = _defaultCoverageFee;
        defaultClaimFee = _defaultClaimFee;
    }

    function setDefaultFees(uint256 _coverageFee, uint256 _claimFee) external onlyOwner {
        if (_coverageFee > MAX_BPS || _claimFee > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        defaultCoverageFee = _coverageFee;
        defaultClaimFee = _claimFee;
        emit DefaultFeesSet(_coverageFee, _claimFee);
    }

    function setSpecialFees(address _user, uint256 _coverageFee, uint256 _claimFee) external onlyOwner {
        if (_coverageFee > MAX_BPS || _claimFee > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        if (_user == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        specialCoverageFee[_user] = _coverageFee;
        specialClaimFee[_user] = _claimFee;
        emit SpecialFeesSet(_user, _coverageFee, _claimFee);
    }

    function getCoverageFee(address _user) public view returns (uint256) {
        return specialCoverageFee[_user] > 0 ? specialCoverageFee[_user] : defaultCoverageFee;
    }

    function getClaimFee(address _user) public view returns (uint256) {
        return specialClaimFee[_user] > 0 ? specialClaimFee[_user] : defaultClaimFee;
    }

    // Coverage fee:
    // formula: Contract_budget * (1 + coverage_fee)
    // 3% if not payed for the freelancer
    // 8% if payed for the freelancer

    function computeCoverageFee(uint256 _amount, uint256 _feeConfig) external view returns (uint256) {
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            return (_amount * (defaultCoverageFee + defaultClaimFee)) / MAX_BPS;
        } else if (_feeConfig == uint256(FeeConfig.ONLY_CLIENT)) {
            return ((_amount * defaultCoverageFee) / MAX_BPS);
        } else if (_feeConfig == uint256(FeeConfig.ONLY_CONTRACTOR)) {
            return ((_amount * defaultClaimFee) / MAX_BPS);
        } else if (_feeConfig == uint256(FeeConfig.FREE)) {
            return 0;
        } else {
            revert EscrowFeeManager__InvalidFeeConfig();
        }
    }

    // Claim fee:
    // formula: Contract_budget * (1 - claim_fee)
    // 5% if not payed by the client
    // 0% if payed by the client

    function computeClaimFee(uint256 _amount, FeeConfig _feeConfig) external returns (uint256) {}

}
