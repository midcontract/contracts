# ERC1271
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/common/ERC1271.sol)

*Abstract contract for validating signatures as per ERC-1271 standard.*


## State Variables
### MAGICVALUE
*Magic value to be returned upon successful signature verification.*


```solidity
bytes4 internal constant MAGICVALUE = 0x1626ba7e;
```


## Functions
### isValidSignature

Returns whether the signature provided is valid for the provided data.


```solidity
function isValidSignature(bytes32 _hash, bytes calldata _signature) public view virtual returns (bytes4);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_hash`|`bytes32`|Hash of the data to be signed.|
|`_signature`|`bytes`|Signature byte array associated with the hash.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4`|The magic value if the signature is valid, otherwise 0xffffffff.|


### _isValidSignature

Internal function to validate the signature.


```solidity
function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view virtual returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_hash`|`bytes32`|Hash of the data to be signed.|
|`_signature`|`bytes`|Signature byte array associated with the hash.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the signature is valid, false otherwise.|


