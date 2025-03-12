# IEscrow
[Git Source](https://github.com/midcontract/contracts/blob/71e459a676c50fe05291a09ea107d28263f8dabb/src/interfaces/IEscrow.sol)

Provides the foundational escrow functionalities common across various types of escrow contracts.


## Functions
### contractExists

Checks if a given contract ID exists.


```solidity
function contractExists(uint256 contractId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractId`|`uint256`|The contract ID to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the contract exists, false otherwise.|


### initialize

Initializes the escrow contract.


```solidity
function initialize(address client, address adminManager, address registry) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`client`|`address`|Address of the client initiating actions within the escrow.|
|`adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`registry`|`address`|Address of the registry contract.|


### transferClientOwnership

Transfers ownership of the client account to a new account.

*Can only be called by the account recovery module registered in the system.*


```solidity
function transferClientOwnership(address newOwner) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOwner`|`address`|The address to which the client ownership will be transferred.|


## Events
### RegistryUpdated
Emitted when the registry address is updated in the escrow.


```solidity
event RegistryUpdated(address registry);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`registry`|`address`|The new registry address.|

### AdminManagerUpdated
*Emitted when the admin manager address is updated in the contract.*


```solidity
event AdminManagerUpdated(address adminManager);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`adminManager`|`address`|The new address of the admin manager.|

### ClientOwnershipTransferred
Event emitted when the ownership of the client account is transferred.


```solidity
event ClientOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`previousOwner`|`address`|The previous owner of the client account.|
|`newOwner`|`address`|The new owner of the client account.|

## Errors
### Escrow__AlreadyInitialized
Thrown when the escrow is already initialized.


```solidity
error Escrow__AlreadyInitialized();
```

### Escrow__UnauthorizedAccount
Thrown when an unauthorized account attempts an action.


```solidity
error Escrow__UnauthorizedAccount(address account);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the unauthorized account.|

### Escrow__ZeroAddressProvided
Thrown when a zero address is provided.


```solidity
error Escrow__ZeroAddressProvided();
```

### Escrow__FeeTooHigh
Thrown when the fee is too high.


```solidity
error Escrow__FeeTooHigh();
```

### Escrow__InvalidStatusToWithdraw
Thrown when the status is invalid for withdrawal.


```solidity
error Escrow__InvalidStatusToWithdraw();
```

### Escrow__InvalidStatusForSubmit
Thrown when the status is invalid for submission.


```solidity
error Escrow__InvalidStatusForSubmit();
```

### Escrow__InvalidContractorDataHash
Thrown when the contractor data hash is invalid.


```solidity
error Escrow__InvalidContractorDataHash();
```

### Escrow__InvalidStatusForApprove
Thrown when the status is invalid for approval.


```solidity
error Escrow__InvalidStatusForApprove();
```

### Escrow__InvalidStatusToClaim
Thrown when the status is invalid to claim.


```solidity
error Escrow__InvalidStatusToClaim();
```

### Escrow__NotEnoughDeposit
Thrown when there is not enough deposit.


```solidity
error Escrow__NotEnoughDeposit();
```

### Escrow__UnauthorizedReceiver
Thrown when the receiver is unauthorized.


```solidity
error Escrow__UnauthorizedReceiver();
```

### Escrow__InvalidAmount
Thrown when the amount is invalid.


```solidity
error Escrow__InvalidAmount();
```

### Escrow__NotApproved
Thrown when the action is not approved.


```solidity
error Escrow__NotApproved();
```

### Escrow__NotSupportedPaymentToken
Thrown when the payment token is not supported.


```solidity
error Escrow__NotSupportedPaymentToken();
```

### Escrow__ZeroDepositAmount
Thrown when the deposit amount is zero.


```solidity
error Escrow__ZeroDepositAmount();
```

### Escrow__InvalidFeeConfig
Thrown when the fee configuration is invalid.


```solidity
error Escrow__InvalidFeeConfig();
```

### Escrow__NotSetFeeManager
Thrown when the fee manager is not set.


```solidity
error Escrow__NotSetFeeManager();
```

### Escrow__NoFundsAvailableForWithdraw
Thrown when no funds are available for withdrawal.


```solidity
error Escrow__NoFundsAvailableForWithdraw();
```

### Escrow__ReturnNotAllowed
Thrown when return is not allowed.


```solidity
error Escrow__ReturnNotAllowed();
```

### Escrow__NoReturnRequested
Thrown when no return is requested.


```solidity
error Escrow__NoReturnRequested();
```

### Escrow__UnauthorizedToApproveReturn
Thrown when unauthorized account tries to approve return.


```solidity
error Escrow__UnauthorizedToApproveReturn();
```

### Escrow__UnauthorizedToApproveDispute
Thrown when unauthorized account tries to approve dispute.


```solidity
error Escrow__UnauthorizedToApproveDispute();
```

### Escrow__CreateDisputeNotAllowed
Thrown when creating dispute is not allowed.


```solidity
error Escrow__CreateDisputeNotAllowed();
```

### Escrow__DisputeNotActiveForThisDeposit
Thrown when dispute is not active for the deposit.


```solidity
error Escrow__DisputeNotActiveForThisDeposit();
```

### Escrow__InvalidStatusProvided
Thrown when the provided status is invalid.


```solidity
error Escrow__InvalidStatusProvided();
```

### Escrow__InvalidWinnerSpecified
Thrown when the specified winner is invalid.


```solidity
error Escrow__InvalidWinnerSpecified();
```

### Escrow__ResolutionExceedsDepositedAmount
Thrown when the resolution exceeds the deposited amount.


```solidity
error Escrow__ResolutionExceedsDepositedAmount();
```

### Escrow__BlacklistedAccount
Thrown when an operation is attempted by an account that is currently blacklisted.


```solidity
error Escrow__BlacklistedAccount();
```

### Escrow__InvalidRange
Thrown when a specified range is invalid, such as an ending index being less than the starting index.


```solidity
error Escrow__InvalidRange();
```

### Escrow__OutOfRange
Thrown when the specified ID is out of the valid range for the contract.


```solidity
error Escrow__OutOfRange();
```

### Escrow__ContractorMismatch
Thrown when the specified contractor does not match the initial contractor set for a given contract ID.


```solidity
error Escrow__ContractorMismatch();
```

### Escrow__AuthorizationExpired
Thrown when the authorization for a deposit has expired.


```solidity
error Escrow__AuthorizationExpired();
```

### Escrow__InvalidSignature
Thrown when the provided signature is invalid during deposit validation.


```solidity
error Escrow__InvalidSignature();
```

### Escrow__ContractIdAlreadyExists
Thrown when the provided `contractId` already exists in storage.


```solidity
error Escrow__ContractIdAlreadyExists();
```

### Escrow__PaymentTokenMismatch
Thrown when the provided payment token does not match the existing contract's payment token.


```solidity
error Escrow__PaymentTokenMismatch();
```

