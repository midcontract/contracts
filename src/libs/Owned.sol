// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Single owner authorization mixin.
/// @author Modified from Solbase (https://github.com/Sol-DAO/solbase/blob/main/src/auth/Owned.sol)
abstract contract Owned {
    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event OwnershipTransferred(address indexed user, address indexed newOwner);

    /// -----------------------------------------------------------------------
    /// Custom Errors
    /// -----------------------------------------------------------------------

    error Owned__Unauthorized();
    error Owned__ZeroAddressProvided();

    /// -----------------------------------------------------------------------
    /// Ownership Storage
    /// -----------------------------------------------------------------------

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Owned__Unauthorized();

        _;
    }

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    /// -----------------------------------------------------------------------
    /// Ownership Logic
    /// -----------------------------------------------------------------------

    /// @dev Transfers ownership of the contract to a new account (`newOwner`).
    /// Can only be called by the current owner.
    function transferOwnership(address newOwner) public payable virtual onlyOwner {
        if (newOwner == address(0)) revert Owned__ZeroAddressProvided();

        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
