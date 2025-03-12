# IEscrowAdminManager
[Git Source](https://github.com/midcontract/contracts/blob/71e459a676c50fe05291a09ea107d28263f8dabb/src/interfaces/IEscrowAdminManager.sol)

Provides interface methods for checking roles in the Escrow Admin Management system.


## Functions
### owner

Retrieves the current owner of the contract.


```solidity
function owner() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the current owner.|


### isAdmin

Determines if a given account has admin privileges.


```solidity
function isAdmin(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to query for admin status.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the specified account is an admin, false otherwise.|


### isGuardian

Determines if a given account is assigned the guardian role.


```solidity
function isGuardian(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to query for guardian status.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the specified account is a guardian, false otherwise.|


### isStrategist

Determines if a given account is assigned the strategist role.


```solidity
function isStrategist(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to query for strategist status.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the specified account is a strategist, false otherwise.|


### isDao

Determines if a given account is assigned the dao role.


```solidity
function isDao(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to query for dao status.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the specified account is a dao, false otherwise.|


## Events
### ETHWithdrawn
Emitted when ETH is successfully withdrawn from the contract.


```solidity
event ETHWithdrawn(address receiver, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|The address that received the withdrawn ETH.|
|`amount`|`uint256`|The amount of ETH withdrawn from the contract.|

## Errors
### ZeroAddressProvided
*Thrown when zero address usage where prohibited.*


```solidity
error ZeroAddressProvided();
```

### ETHTransferFailed
Thrown when an ETH transfer failed.


```solidity
error ETHTransferFailed();
```

