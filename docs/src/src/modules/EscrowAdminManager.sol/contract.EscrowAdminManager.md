# EscrowAdminManager
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/modules/EscrowAdminManager.sol)

**Inherits:**
OwnedRoles

Manages administrative roles and permissions for the escrow system, using a role-based access control mechanism.

*This contract extends OwnedRoles to utilize its role management functionalities and establishes predefined roles such as Admin, Guardian, and Strategist.
It includes references to unused role constants defined in the OwnedRoles library, which are part of the library's design to accommodate potential future roles.
These constants do not affect the contract's functionality or gas efficiency but are retained for compatibility and future flexibility.*


## State Variables
### ADMIN_ROLE

```solidity
uint256 private constant ADMIN_ROLE = 1 << 1;
```


### GUARDIAN_ROLE

```solidity
uint256 private constant GUARDIAN_ROLE = 1 << 2;
```


### STRATEGIST_ROLE

```solidity
uint256 private constant STRATEGIST_ROLE = 1 << 3;
```


### DAO_ROLE

```solidity
uint256 private constant DAO_ROLE = 1 << 4;
```


## Functions
### constructor

*Initializes the contract by setting the initial owner and granting them the Admin role.*


```solidity
constructor(address _initialOwner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_initialOwner`|`address`|Address of the initial owner of the contract.|


### addAdmin

Grants the Admin role to a specified address.


```solidity
function addAdmin(address _admin) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_admin`|`address`|Address to which the Admin role will be granted.|


### removeAdmin

Revokes the Admin role from a specified address.


```solidity
function removeAdmin(address _admin) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_admin`|`address`|Address from which the Admin role will be revoked.|


### addGuardian

Grants the Guardian role to a specified address.


```solidity
function addGuardian(address _guardian) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_guardian`|`address`|Address to which the Guardian role will be granted.|


### removeGuardian

Revokes the Guardian role from a specified address.


```solidity
function removeGuardian(address _guardian) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_guardian`|`address`|Address from which the Guardian role will be revoked.|


### addStrategist

Grants the Strategist role to a specified address.


```solidity
function addStrategist(address _strategist) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_strategist`|`address`|Address to which the Strategist role will be granted.|


### removeStrategist

Revokes the Strategist role from a specified address.


```solidity
function removeStrategist(address _strategist) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_strategist`|`address`|Address from which the Strategist role will be revoked.|


### addDaoAccount

Grants the Dao role to a specified address.


```solidity
function addDaoAccount(address _daoAccount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_daoAccount`|`address`|Address to which the Dao role will be granted.|


### removeDaoAccount

Revokes the Dao role from a specified address.


```solidity
function removeDaoAccount(address _daoAccount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_daoAccount`|`address`|Address from which the Dao role will be revoked.|


### isAdmin

Checks if a specified address has the Admin role.


```solidity
function isAdmin(address _account) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_account`|`address`|Address to check for the Admin role.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address has the Admin role, otherwise false.|


### isGuardian

Checks if a specified address has the Guardian role.


```solidity
function isGuardian(address _account) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_account`|`address`|Address to check for the Guardian role.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address has the Guardian role, otherwise false.|


### isStrategist

Checks if a specified address has the Strategist role.


```solidity
function isStrategist(address _account) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_account`|`address`|Address to check for the Strategist role.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address has the Strategist role, otherwise false.|


### isDao

Checks if a specified address has the Dao role.


```solidity
function isDao(address _account) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_account`|`address`|Address to check for the Dao role.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address has the Dao role, otherwise false.|


