// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowFeeManager} from "../interfaces/IEscrowFeeManager.sol";
import {Owned} from "../libs/Owned.sol";

contract EscrowFeeManager is IEscrowFeeManager, Owned {
    /// @notice The basis points used for calculating fees and percentages.
    uint256 public constant MAX_BPS = 100_00; // 100%

    struct FeeRates {
        uint16 coverage; // Coverage fee percentage
        uint16 claim; // Claim fee percentage
    }

    FeeRates public defaultFees;

    mapping(address user => FeeRates feeType) public specialFees;

    enum FeeConfig {
        CLIENT_COVERS_ALL, // Client pays both coverage and claim fees (total 8%)
        CLIENT_COVERS_ONLY, // Client pays only the coverage fee (3%), contractor responsible for the claim fee (5%)
        CONTRACTOR_COVERS_CLAIM, // Contractor pays the claim fee (5%), no coverage fee applied
        NO_FEES // No fees applied (0%)

    }

    constructor(uint16 _coverage, uint16 _claim) Owned(msg.sender) {
        updateDefaultFees(_coverage, _claim);
    }

    function updateDefaultFees(uint16 _coverage, uint16 _claim) public onlyOwner {
        if (_coverage > MAX_BPS || _claim > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        defaultFees = FeeRates({coverage: _coverage, claim: _claim});
        emit DefaultFeesSet(_coverage, _claim);
    }

    function setSpecialFees(address _user, uint16 _coverage, uint16 _claim) external onlyOwner {
        if (_coverage > MAX_BPS || _claim > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        if (_user == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        specialFees[_user] = FeeRates({coverage: _coverage, claim: _claim});
        emit SpecialFeesSet(_user, _coverage, _claim);
    }

    function computeDepositAmount(address _client, uint256 _depositAmount, FeeConfig _feeConfig)
        external
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        FeeRates memory rates =
            (specialFees[_client].coverage != 0 || specialFees[_client].claim != 0) ? specialFees[_client] : defaultFees;

        if (_feeConfig == FeeConfig.CLIENT_COVERS_ALL) {
            // If the client covers both the coverage and claim fees
            feeApplied = _depositAmount * (rates.coverage + rates.claim) / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else if (_feeConfig == FeeConfig.CLIENT_COVERS_ONLY) {
            // If the client only covers the coverage fee
            feeApplied = _depositAmount * rates.coverage / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else {
            // No fees applied
            totalDepositAmount = _depositAmount;
            feeApplied = 0;
        }

        return (totalDepositAmount, feeApplied);
    }

    function computeClaimableAmount(address _contractor, uint256 _claimedAmount, FeeConfig _feeConfig)
        external
        view
        returns (uint256 claimableAmount, uint256 feeDeducted)
    {
        FeeRates memory rates = (specialFees[_contractor].claim != 0) ? specialFees[_contractor] : defaultFees;

        if (_feeConfig == FeeConfig.CLIENT_COVERS_ALL) {
            claimableAmount = _claimedAmount;
            feeDeducted = 0;
        } else if (_feeConfig == FeeConfig.CONTRACTOR_COVERS_CLAIM || _feeConfig == FeeConfig.CLIENT_COVERS_ONLY) {
            feeDeducted = _claimedAmount * rates.claim / MAX_BPS;
            claimableAmount = _claimedAmount - feeDeducted;
        } else {
            claimableAmount = _claimedAmount;
            feeDeducted = 0;
        }

        return (claimableAmount, feeDeducted);
    }

    function getCoverageFee(address _user) external view returns (uint256) {
        return specialFees[_user].coverage > 0 ? specialFees[_user].coverage : defaultFees.coverage;
    }

    function getClaimFee(address _user) external view returns (uint256) {
        return specialFees[_user].claim > 0 ? specialFees[_user].claim : defaultFees.claim;
    }
}
