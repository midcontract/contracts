// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ECDSA} from "./ECDSA.sol";

/// @title ERC1271
/// @dev Abstract contract for validating signatures as per ERC-1271 standard.
abstract contract ERC1271 {
    using ECDSA for bytes32;

    /// @dev Magic value to be returned upon successful signature verification.
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    /// @notice Returns whether the signature provided is valid for the provided data.
    /// @param _hash Hash of the data to be signed.
    /// @param _signature Signature byte array associated with the hash.
    /// @return The magic value if the signature is valid, otherwise 0xffffffff.
    function isValidSignature(bytes32 _hash, bytes calldata _signature) public view virtual returns (bytes4) {
        if (_isValidSignature(_hash, _signature)) {
            return MAGICVALUE;
        } else {
            return 0xffffffff;
        }
    }
    
    /// @notice Internal function to validate the signature.
    /// @param _hash Hash of the data to be signed.
    /// @param _signature Signature byte array associated with the hash.
    /// @return True if the signature is valid, false otherwise.
    function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view virtual returns (bool);
}
