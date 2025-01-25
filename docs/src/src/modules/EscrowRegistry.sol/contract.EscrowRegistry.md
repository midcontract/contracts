# EscrowRegistry
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/modules/EscrowRegistry.sol)

**Inherits:**
[IEscrowRegistry](/src/interfaces/IEscrowRegistry.sol/interface.IEscrowRegistry.md), OwnedThreeStep

*This contract manages configuration settings for the escrow system including approved payment tokens.*


## State Variables
### NATIVE_TOKEN
Constant for the native token of the chain.

*Used to represent the native blockchain currency in payment tokens mapping.*


```solidity
address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```


### escrowFixedPrice
Address of the escrow fixed price contract currently in use.


```solidity
address public escrowFixedPrice;
```


### escrowHourly
Address of the escrow hourly contract currently in use.


```solidity
address public escrowHourly;
```


### escrowMilestone
Address of the escrow milestone contract currently in use.


```solidity
address public escrowMilestone;
```


### factory
Address of the factory contract currently in use.

*This can be updated by the owner as new versions of the Factory contract are deployed.*


```solidity
address public factory;
```


### feeManager
Address of the fee manager contract currently in use.

*This can be updated by the owner as new versions of the FeeManager contract are deployed.*


```solidity
address public feeManager;
```


### fixedTreasury
Address of the treasury designated for fixed-price escrow contracts.


```solidity
address public fixedTreasury;
```


### hourlyTreasury
Address of the treasury designated for hourly escrow contracts.


```solidity
address public hourlyTreasury;
```


### milestoneTreasury
Address of the treasury designated for milestone escrow contracts.


```solidity
address public milestoneTreasury;
```


### accountRecovery
Address of the account recovery module contract.


```solidity
address public accountRecovery;
```


### adminManager
Address of the admin manager contract.


```solidity
address public adminManager;
```


### paymentTokens
Mapping of token addresses allowed for use as payment in escrows.

*Initially includes ERC20 stablecoins and optionally wrapped native tokens.
This setting can be updated to reflect changes in allowed payment methods, adhering to security and usability
standards.*


```solidity
mapping(address token => bool enabled) public paymentTokens;
```


### blacklist
Checks if an address is blacklisted.
Blacklisted addresses are restricted from participating in certain transactions
to enhance security and compliance, particularly with anti-money laundering (AML) regulations.

*Stores addresses that are blacklisted from participating in transactions.*


```solidity
mapping(address user => bool blacklisted) public blacklist;
```


## Functions
### constructor

*Initializes the contract setting the owner to the message sender.*


```solidity
constructor(address _owner) OwnedThreeStep(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|Address of the initial owner of the registry contract.|


### addPaymentToken

Adds a new ERC20 token to the list of accepted payment tokens.


```solidity
function addPaymentToken(address _token) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The address of the ERC20 token to enable.|


### removePaymentToken

Removes an ERC20 token from the list of accepted payment tokens.


```solidity
function removePaymentToken(address _token) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The address of the ERC20 token to disable.|


### updateEscrowFixedPrice

Updates the address of the escrow fixed price contract.


```solidity
function updateEscrowFixedPrice(address _escrowFixedPrice) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowFixedPrice`|`address`|The new address of the EscrowFixedPrice contract to be used.|


### updateEscrowMilestone

Updates the address of the escrow milestone contract.


```solidity
function updateEscrowMilestone(address _escrowMilestone) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowMilestone`|`address`|The new address of the EscrowMilestone contract to be used.|


### updateEscrowHourly

Updates the address of the escrow hourly contract.


```solidity
function updateEscrowHourly(address _escrowHourly) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowHourly`|`address`|The new address of the EscrowHourly contract to be used.|


### updateFactory

Updates the address of the factory contract.


```solidity
function updateFactory(address _factory) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_factory`|`address`|The new address of the Factory contract to be used.|


### updateFeeManager

Updates the address of the fee manager contract.


```solidity
function updateFeeManager(address _feeManager) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_feeManager`|`address`|The new address of the FeeManager contract to be used.|


### setFixedTreasury

Sets the treasury address designated for fixed-price escrow contracts.


```solidity
function setFixedTreasury(address _fixedTreasury) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_fixedTreasury`|`address`|The new address of the fixed-price escrow treasury.|


### setHourlyTreasury

Sets the treasury address designated for hourly escrow contracts.


```solidity
function setHourlyTreasury(address _hourlyTreasury) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_hourlyTreasury`|`address`|The new address of the hourly escrow treasury.|


### setMilestoneTreasury

Sets the treasury address designated for milestone escrow contracts.


```solidity
function setMilestoneTreasury(address _milestoneTreasury) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_milestoneTreasury`|`address`|The new address of the milestone escrow treasury.|


### setAccountRecovery

Updates the address of the account recovery module contract.


```solidity
function setAccountRecovery(address _accountRecovery) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_accountRecovery`|`address`|The new address of the AccountRecovery module contract to be used.|


### setAdminManager

Updates the address of the admin manager contract.


```solidity
function setAdminManager(address _adminManager) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|The new address of the AdminManager contract to be used.|


### addToBlacklist

Adds an address to the blacklist.


```solidity
function addToBlacklist(address _user) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to add to the blacklist.|


### removeFromBlacklist

Removes an address from the blacklist.


```solidity
function removeFromBlacklist(address _user) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to remove from the blacklist.|


### withdrawETH

Withdraws any ETH accidentally sent to the contract.


```solidity
function withdrawETH(address _receiver) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_receiver`|`address`|The address that will receive the withdrawn ETH.|


