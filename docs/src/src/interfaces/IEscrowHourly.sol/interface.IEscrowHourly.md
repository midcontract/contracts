# IEscrowHourly
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/interfaces/IEscrowHourly.sol)

**Inherits:**
[IEscrow](/src/interfaces/IEscrow.sol/interface.IEscrow.md)

Interface for managing hourly-based escrow agreements.
Focuses on the declaration of structs, events, errors, and essential function signatures to support hourly-based
operations within the escrow system.


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
    address indexed sender,
    uint256 indexed contractId,
    uint256 weekId,
    uint256 totalDepositAmount,
    address indexed contractor
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`weekId`|`uint256`|The ID of the week.|
|`totalDepositAmount`|`uint256`|The total amount deposited: principal + platform fee.|
|`contractor`|`address`|The address of the contractor.|

### Approved
Emitted when an approval is made.


```solidity
event Approved(
    address indexed approver, uint256 indexed contractId, uint256 weekId, uint256 amountApprove, address receiver
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`weekId`|`uint256`|The ID of the week.|
|`amountApprove`|`uint256`|The approved amount.|
|`receiver`|`address`|The address of the receiver.|

### RefilledPrepayment
Emitted when the prepayment for a contract is refilled.


```solidity
event RefilledPrepayment(address indexed sender, uint256 indexed contractId, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`amount`|`uint256`|The additional amount added.|

### RefilledWeekPayment
Emitted when a contract is refilled.


```solidity
event RefilledWeekPayment(address indexed sender, uint256 indexed contractId, uint256 weekId, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`weekId`|`uint256`|The ID of the week.|
|`amount`|`uint256`|The additional amount added.|

### Claimed
Emitted when a claim is made.


```solidity
event Claimed(
    address indexed contractor,
    uint256 indexed contractId,
    uint256 weekId,
    uint256 amount,
    uint256 feeAmount,
    address indexed client
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor.|
|`contractId`|`uint256`|The ID of the contract.|
|`weekId`|`uint256`|The ID of the week.|
|`amount`|`uint256`|The net amount claimed by the contractor, after deducting fees.|
|`feeAmount`|`uint256`|The fee amount paid by the contractor for the claim.|
|`client`|`address`|The address of the client associated with the contract.|

### BulkClaimed
Emitted when a contractor claims amounts from multiple weeks in one transaction.


```solidity
event BulkClaimed(
    address indexed contractor,
    uint256 indexed contractId,
    uint256 startWeekId,
    uint256 endWeekId,
    uint256 totalClaimedAmount,
    uint256 totalFeeAmount,
    uint256 totalClientFee,
    address indexed client
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor who performed the bulk claim.|
|`contractId`|`uint256`|The identifier of the contract within which the bulk claim was made.|
|`startWeekId`|`uint256`|The starting week ID of the range within which the claims were made.|
|`endWeekId`|`uint256`|The ending week ID of the range within which the claims were made.|
|`totalClaimedAmount`|`uint256`|The total amount claimed across all weeks in the specified range.|
|`totalFeeAmount`|`uint256`|The total fee amount deducted from the claims.|
|`totalClientFee`|`uint256`|The total additional fee paid by the client related to the claims.|
|`client`|`address`|The address of the client associated with the contract.|

### Withdrawn
Emitted when a withdrawal is made.


```solidity
event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount, uint256 feeAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`withdrawer`|`address`|The address of the withdrawer.|
|`contractId`|`uint256`|The ID of the contract.|
|`amount`|`uint256`|The net amount withdrawn, after deducting fees.|
|`feeAmount`|`uint256`|The fee amount paid by the withdrawer for the withdrawal, if applicable.|

### ReturnRequested
Emitted when a return is requested.

*Currently focuses on the return of prepayment amounts but includes a `weekId` for potential future use
where returns might be processed on a week-by-week basis.*


```solidity
event ReturnRequested(address indexed sender, uint256 indexed contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|

### ReturnApproved
Emitted when a return is approved.


```solidity
event ReturnApproved(address indexed approver, uint256 indexed contractId, address indexed client);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`client`|`address`|The address of the client associated with the contract.|

### ReturnCanceled
Emitted when a return is canceled.


```solidity
event ReturnCanceled(address indexed sender, uint256 indexed contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|

### DisputeCreated
Emitted when a dispute is created.


```solidity
event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 weekId, address indexed client);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`weekId`|`uint256`|The ID of the week.|
|`client`|`address`|The address of the client associated with the contract.|

### DisputeResolved
Emitted when a dispute is resolved.


```solidity
event DisputeResolved(
    address indexed approver,
    uint256 indexed contractId,
    uint256 weekId,
    Enums.Winner winner,
    uint256 clientAmount,
    uint256 contractorAmount,
    address indexed client
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`weekId`|`uint256`|The ID of the week.|
|`winner`|`Enums.Winner`|The winner of the dispute.|
|`clientAmount`|`uint256`|The amount awarded to the client.|
|`contractorAmount`|`uint256`|The amount awarded to the contractor.|
|`client`|`address`|The address of the client associated with the contract.|

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

## Errors
### Escrow__NoDepositsProvided
Thrown when no deposits are provided in a function call that expects at least one.


```solidity
error Escrow__NoDepositsProvided();
```

### Escrow__InvalidContractId
Thrown when an invalid contract ID is provided to a function expecting a valid existing contract ID.


```solidity
error Escrow__InvalidContractId();
```

### Escrow__InvalidWeekId
Thrown when an invalid week ID is provided to a function expecting a valid week ID within range.


```solidity
error Escrow__InvalidWeekId();
```

### Escrow__InsufficientPrepayment
Thrown when the available prepayment amount is insufficient to cover the requested operation.


```solidity
error Escrow__InsufficientPrepayment();
```

## Structs
### DepositRequest
Represents the input parameters required for initializing or adding to a deposit with authorization in
the hourly escrow.

*This struct is used as a payload to authorize deposit requests and validate them against admin-signed
approvals.*


```solidity
struct DepositRequest {
    uint256 contractId;
    address contractor;
    address paymentToken;
    uint256 prepaymentAmount;
    uint256 amountToClaim;
    Enums.FeeConfig feeConfig;
    address escrow;
    uint256 expiration;
    bytes signature;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`contractId`|`uint256`|The ID of the contract associated with the deposit.|
|`contractor`|`address`|The address of the contractor responsible for fulfilling the contract work.|
|`paymentToken`|`address`|The address of the ERC20 token used as payment in the deposit.|
|`prepaymentAmount`|`uint256`|The upfront payment amount made as part of the contract deposit.|
|`amountToClaim`|`uint256`|The amount that can be claimed by the contractor upon completion.|
|`feeConfig`|`Enums.FeeConfig`|Configuration specifying how platform fees are applied to the deposit.|
|`escrow`|`address`|The address of the escrow contract managing this deposit.|
|`expiration`|`uint256`|The UNIX timestamp after which the deposit request is considered invalid and cannot be processed.|
|`signature`|`bytes`|The cryptographic signature generated by the admin to authorize and validate the deposit request.|

### ContractDetails
Holds detailed information about a contract's settings and status.


```solidity
struct ContractDetails {
    address contractor;
    address paymentToken;
    uint256 prepaymentAmount;
    uint256 amountToWithdraw;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor assigned to the contract.|
|`paymentToken`|`address`|The token used for financial transactions within the contract.|
|`prepaymentAmount`|`uint256`|The total amount prepaid by the client, setting the financial basis for the contract.|
|`amountToWithdraw`|`uint256`|The total amount available for withdrawal post-completion or approval.|
|`feeConfig`|`Enums.FeeConfig`|The fee configuration, dictating how fees are calculated and allocated.|
|`status`|`Enums.Status`|The current status of the contract, indicating its phase within the lifecycle.|

### WeeklyEntry
Represents the claim details and status for a weekly billing cycle in an escrow contract.


```solidity
struct WeeklyEntry {
    uint256 amountToClaim;
    Enums.Status weekStatus;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`amountToClaim`|`uint256`|Amount set for the contractor to claim upon completion of weekly tasks.|
|`weekStatus`|`Enums.Status`|Operational status of the week, indicating claim readiness or dispute status.|

