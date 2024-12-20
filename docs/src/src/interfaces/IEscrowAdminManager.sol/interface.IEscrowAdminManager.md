# IEscrowAdminManager
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/interfaces/IEscrowAdminManager.sol)

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


