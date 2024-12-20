# IEscrowFixedPrice
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/interfaces/IEscrowFixedPrice.sol)

**Inherits:**
[IEscrow](/src/interfaces/IEscrow.sol/interface.IEscrow.md)

Interface for managing fixed-price escrow agreements within the system, focusing on defining common events
and errors.
Defines only the essential components such as errors, events, struct and key function signatures related to
fixed-price escrow operations.


## Functions
### transferContractorOwnership

Interface declaration for transferring contractor ownership.


```solidity
function transferContractorOwnership(uint256 contractId, address newOwner) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
|`newOwner`|`address`|The address to which the contractor ownership will be transferred.|


## Events
### Deposited
Emitted when a deposit is made.


```solidity
event Deposited(
    address indexed depositor, uint256 indexed contractId, uint256 totalDepositAmount, address indexed contractor
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositor`|`address`|The address of the depositor.|
|`contractId`|`uint256`|The ID of the contract.|
|`totalDepositAmount`|`uint256`|The total amount deposited: principal + platform fee.|
|`contractor`|`address`|The address of the contractor.|

### Submitted
Emitted when a submission is made.


```solidity
event Submitted(address indexed sender, uint256 indexed contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|

### Approved
Emitted when an approval is made.


```solidity
event Approved(address indexed approver, uint256 indexed contractId, uint256 amountApprove, address indexed receiver);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`amountApprove`|`uint256`|The approved amount.|
|`receiver`|`address`|The address of the receiver.|

### Refilled
Emitted when a contract is refilled.


```solidity
event Refilled(address indexed sender, uint256 indexed contractId, uint256 amountAdditional);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`amountAdditional`|`uint256`|The additional amount added.|

### Claimed
Emitted when a claim is made by the contractor.


```solidity
event Claimed(address indexed contractor, uint256 indexed contractId, uint256 amount, uint256 feeAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor making the claim.|
|`contractId`|`uint256`|The ID of the contract associated with the claim.|
|`amount`|`uint256`|The net amount claimed by the contractor, after deducting fees.|
|`feeAmount`|`uint256`|The fee amount paid by the contractor for the claim.|

### Withdrawn
Emitted when a withdrawal is made by a withdrawer.


```solidity
event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount, uint256 feeAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`withdrawer`|`address`|The address of the withdrawer executing the withdrawal.|
|`contractId`|`uint256`|The ID of the contract associated with the withdrawal.|
|`amount`|`uint256`|The net amount withdrawn by the withdrawer, after deducting fees.|
|`feeAmount`|`uint256`|The fee amount paid by the withdrawer for the withdrawal, if applicable.|

### ReturnRequested
Emitted when a return is requested.


```solidity
event ReturnRequested(address indexed sender, uint256 contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|

### ReturnApproved
Emitted when a return is approved.


```solidity
event ReturnApproved(address indexed approver, uint256 contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|

### ReturnCanceled
Emitted when a return is canceled.


```solidity
event ReturnCanceled(address indexed sender, uint256 contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|

### DisputeCreated
Emitted when a dispute is created.


```solidity
event DisputeCreated(address indexed sender, uint256 contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|

### DisputeResolved
Emitted when a dispute is resolved.


```solidity
event DisputeResolved(
    address indexed approver, uint256 contractId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`winner`|`Enums.Winner`|The winner of the dispute.|
|`clientAmount`|`uint256`|The amount awarded to the client.|
|`contractorAmount`|`uint256`|The amount awarded to the contractor.|

### ContractorOwnershipTransferred
Emitted when the ownership of a contractor account is transferred to a new owner.


```solidity
event ContractorOwnershipTransferred(
    uint256 indexed contractId, address indexed previousOwner, address indexed newOwner
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
|`previousOwner`|`address`|The previous owner of the contractor account.|
|`newOwner`|`address`|The new owner of the contractor account.|

## Structs
### Deposit
Represents a deposit in the escrow.


```solidity
struct Deposit {
    address contractor;
    address paymentToken;
    uint256 amount;
    uint256 amountToClaim;
    uint256 amountToWithdraw;
    bytes32 contractorData;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor.|
|`paymentToken`|`address`|The address of the payment token.|
|`amount`|`uint256`|The amount deposited.|
|`amountToClaim`|`uint256`|The amount to be claimed.|
|`amountToWithdraw`|`uint256`|The amount to be withdrawn.|
|`contractorData`|`bytes32`|The contractor's data hash.|
|`feeConfig`|`Enums.FeeConfig`|The fee configuration.|
|`status`|`Enums.Status`|The status of the deposit.|
