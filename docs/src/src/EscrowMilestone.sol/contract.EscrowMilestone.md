# EscrowMilestone
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/EscrowMilestone.sol)

**Inherits:**
[IEscrowMilestone](/src/interfaces/IEscrowMilestone.sol/interface.IEscrowMilestone.md), [ERC1271](/src/common/ERC1271.sol/abstract.ERC1271.md)

Facilitates the management of milestones within escrow contracts, including the creation, modification, and
completion of milestones.


## State Variables
### adminManager
*Address of the adminManager contract.*


```solidity
IEscrowAdminManager public adminManager;
```


### registry
*Address of the registry contract.*


```solidity
IEscrowRegistry public registry;
```


### client
*Address of the client who initiates the escrow contract.*


```solidity
address public client;
```


### currentContractId
*Tracks the last issued contract ID, incrementing with each new contract creation.*


```solidity
uint256 private currentContractId;
```


### maxMilestones
The maximum number of milestones that can be processed in a single transaction.


```solidity
uint256 public maxMilestones;
```


### initialized
*Indicates that the contract has been initialized.*


```solidity
bool public initialized;
```


### contractMilestones
*Maps each contract ID to an array of `Milestone` structs, representing the milestones of the contract.*


```solidity
mapping(uint256 contractId => Milestone[]) public contractMilestones;
```


### milestoneDetails
*Maps each contract and milestone ID pair to its corresponding MilestoneDetails.*


```solidity
mapping(uint256 contractId => mapping(uint256 milestoneId => MilestoneDetails)) public milestoneDetails;
```


## Functions
### onlyClient

*Modifier to restrict functions to the client address.*


```solidity
modifier onlyClient();
```

### initialize

Initializes the escrow contract.


```solidity
function initialize(address _client, address _adminManager, address _registry) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_client`|`address`|Address of the client initiating actions within the escrow.|
|`_adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`_registry`|`address`|Address of the registry contract.|


### deposit

Creates multiple milestones for a new or existing contract.

*This function allows the initialization of multiple milestones in a single transaction,
either by creating a new contract or adding to an existing one. Uses the adjustable limit `maxMilestones`
to prevent gas limit issues.*


```solidity
function deposit(uint256 _contractId, address _paymentToken, Milestone[] calldata _milestones) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract for which the deposits are made; if zero, a new contract is initialized.|
|`_paymentToken`|`address`| The address of the payment token for the contractId.|
|`_milestones`|`Milestone[]`|Array of details for each new milestone.|


### submit

Submits work for a milestone by the contractor.

*This function allows the contractor to submit their work details for a milestone.*


```solidity
function submit(uint256 _contractId, uint256 _milestoneId, bytes calldata _data, bytes32 _salt) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract containing the milestone.|
|`_milestoneId`|`uint256`|ID of the milestone to submit work for.|
|`_data`|`bytes`|Contractor’s details or work summary.|
|`_salt`|`bytes32`|Unique salt for cryptographic operations.|


### approve

Approves a milestone's submitted work, specifying the amount to release to the contractor.

*This function allows the client or an authorized admin to approve work submitted for a milestone,
specifying the amount to be released.*


```solidity
function approve(uint256 _contractId, uint256 _milestoneId, uint256 _amountApprove, address _receiver) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract containing the milestone.|
|`_milestoneId`|`uint256`|ID of the milestone within the contract to be approved.|
|`_amountApprove`|`uint256`|Amount to be released for the milestone.|
|`_receiver`|`address`|Address of the contractor receiving the approved amount.|


### refill

Adds additional funds to a milestone's budget within a contract.

*Allows a client to add funds to a specific milestone, updating the total deposit amount for that milestone.*


```solidity
function refill(uint256 _contractId, uint256 _milestoneId, uint256 _amountAdditional) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract containing the milestone.|
|`_milestoneId`|`uint256`|ID of the milestone within the contract to be refilled.|
|`_amountAdditional`|`uint256`|The additional amount to be added to the milestone's budget.|


### claim

Allows the contractor to claim the approved amount for a milestone within a contract.

*Handles the transfer of approved amounts to the contractor while adjusting for any applicable fees.*


```solidity
function claim(uint256 _contractId, uint256 _milestoneId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract containing the milestone.|
|`_milestoneId`|`uint256`|ID of the milestone from which funds are to be claimed.|


### claimAll

Claims all approved amounts by the contractor for a given contract.

*Allows the contractor to claim for multiple milestones in a specified range.*


```solidity
function claimAll(uint256 _contractId, uint256 _startMilestoneId, uint256 _endMilestoneId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract from which to claim funds.|
|`_startMilestoneId`|`uint256`|Starting milestone ID from which to begin claims.|
|`_endMilestoneId`|`uint256`|Ending milestone ID until which claims are made. This function mitigates gas exhaustion issues by allowing batch processing within a specified limit.|


### withdraw

Withdraws funds from a milestone under specific conditions.

*Withdrawal depends on the milestone being approved for refund or resolved.*


```solidity
function withdraw(uint256 _contractId, uint256 _milestoneId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The identifier of the contract from which to withdraw funds.|
|`_milestoneId`|`uint256`|The identifier of the milestone within the contract from which to withdraw funds.|


### requestReturn

Requests the return of funds by the client for a specific milestone.

*The milestone must be in an eligible state to request a return (not in disputed or already returned
status).*


```solidity
function requestReturn(uint256 _contractId, uint256 _milestoneId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit for which the return is requested.|
|`_milestoneId`|`uint256`|ID of the milestone for which the return is requested.|


### approveReturn

Approves the return of funds, which can be called by the contractor or platform admin.

*This changes the status of the milestone to allow the client to withdraw their funds.*


```solidity
function approveReturn(uint256 _contractId, uint256 _milestoneId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the milestone for which the return is approved.|
|`_milestoneId`|`uint256`|ID of the milestone for which the return is approved.|


### cancelReturn

Cancels a previously requested return and resets the milestone's status.

*Allows reverting the milestone status from RETURN_REQUESTED to an active state.*


```solidity
function cancelReturn(uint256 _contractId, uint256 _milestoneId, Enums.Status _status) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The unique identifier of the milestone for which the return is being cancelled.|
|`_milestoneId`|`uint256`|ID of the milestone for which the return is being cancelled.|
|`_status`|`Enums.Status`|The new status to set for the milestone, must be ACTIVE, SUBMITTED, APPROVED, or COMPLETED.|


### createDispute

Creates a dispute over a specific milestone.

*Initiates a dispute status for a milestone that can be activated by the client or contractor
when they disagree on the previously submitted work.*


```solidity
function createDispute(uint256 _contractId, uint256 _milestoneId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the milestone where the dispute occurred.|
|`_milestoneId`|`uint256`|ID of the milestone where the dispute occurred. This function can only be called if the milestone status is either RETURN_REQUESTED or SUBMITTED.|


### resolveDispute

Resolves a dispute over a specific milestone.

*Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
Admin intervention is required to resolve disputes to ensure fairness.*


```solidity
function resolveDispute(
    uint256 _contractId,
    uint256 _milestoneId,
    Enums.Winner _winner,
    uint256 _clientAmount,
    uint256 _contractorAmount
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the milestone where the dispute occurred.|
|`_milestoneId`|`uint256`|ID of the milestone where the dispute occurred.|
|`_winner`|`Enums.Winner`|Specifies who the winner is: Client, Contractor, or Split.|
|`_clientAmount`|`uint256`|Amount to be allocated to the client if Split or Client wins.|
|`_contractorAmount`|`uint256`|Amount to be allocated to the contractor if Split or Contractor wins. This function ensures that the total resolution amounts do not exceed the deposited amount and adjusts the status of the milestone based on the dispute outcome.|


### transferClientOwnership

Transfers ownership of the client account to a new account.

*Can only be called by the account recovery module registered in the system.*


```solidity
function transferClientOwnership(address _newAccount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newAccount`|`address`|The address to which the client ownership will be transferred.|


### transferContractorOwnership

Transfers ownership of the contractor account to a new account for a specified contract.

*Can only be called by the account recovery module registered in the system.*


```solidity
function transferContractorOwnership(uint256 _contractId, uint256 _milestoneId, address _newAccount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
|`_milestoneId`|`uint256`|The identifier of the milestone for which contractor ownership is being transferred.|
|`_newAccount`|`address`|The address to which the contractor ownership will be transferred.|


### updateRegistry

Updates the registry address used for fetching escrow implementations.


```solidity
function updateRegistry(address _registry) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|New registry address.|


### updateAdminManager

Updates the address of the admin manager contract.

*Restricts the function to be callable only by the current owner of the admin manager.*


```solidity
function updateAdminManager(address _adminManager) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|The new address of the admin manager contract.|


### setMaxMilestones

Sets the maximum number of milestones that can be added in a single transaction.

*This limit helps prevent gas limit issues during bulk operations and can be adjusted by the contract admin.*


```solidity
function setMaxMilestones(uint256 _maxMilestones) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_maxMilestones`|`uint256`|The new maximum number of milestones.|


### getCurrentContractId

Retrieves the current contract ID.


```solidity
function getCurrentContractId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The current contract ID.|


### getMilestoneCount

Retrieves the number of milestones for a given contract ID.


```solidity
function getMilestoneCount(uint256 _contractId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The contract ID for which to retrieve the milestone count.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of milestones associated with the given contract ID.|


### getContractorDataHash

Generates a hash for the contractor data.

*This external function computes the hash value for the contractor data using the provided data and salt.*


```solidity
function getContractorDataHash(bytes calldata _data, bytes32 _salt) external pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_data`|`bytes`|Contractor data.|
|`_salt`|`bytes32`|Salt value for generating the hash.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Hash value of the contractor data.|


### _getContractorDataHash

Generates a hash for the contractor data.

*This internal function computes the hash value for the contractor data using the provided data and salt.*


```solidity
function _getContractorDataHash(bytes calldata _data, bytes32 _salt) internal pure returns (bytes32);
```

### _computeDepositAmountAndFee

Computes the total deposit amount and the applied fee.

*This internal function calculates the total deposit amount and the fee applied based on the client, deposit
amount, and fee configuration.*


```solidity
function _computeDepositAmountAndFee(
    uint256 _contractId,
    address _client,
    uint256 _depositAmount,
    Enums.FeeConfig _feeConfig
) internal view returns (uint256 totalDepositAmount, uint256 feeApplied);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`_client`|`address`|Address of the client making the deposit.|
|`_depositAmount`|`uint256`|Amount of the deposit.|
|`_feeConfig`|`Enums.FeeConfig`|Fee configuration for the deposit.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalDepositAmount`|`uint256`|Total deposit amount after applying the fee.|
|`feeApplied`|`uint256`|Fee applied to the deposit.|


### _computeClaimableAmountAndFee

Computes the claimable amount and the fee deducted from the claimed amount.

*This internal function calculates the claimable amount for the contractor and the fees deducted from the
claimed amount based on the contractor, claimed amount, and fee configuration.*


```solidity
function _computeClaimableAmountAndFee(
    uint256 _contractId,
    address _contractor,
    uint256 _claimedAmount,
    Enums.FeeConfig _feeConfig
) internal view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`_contractor`|`address`|Address of the contractor claiming the amount.|
|`_claimedAmount`|`uint256`|Amount claimed by the contractor.|
|`_feeConfig`|`Enums.FeeConfig`|Fee configuration for the deposit.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimableAmount`|`uint256`|Amount claimable by the contractor.|
|`feeDeducted`|`uint256`|Fee deducted from the claimed amount.|
|`clientFee`|`uint256`|Fee to be paid by the client for covering the claim.|


### _sendPlatformFee

Sends the platform fee to the treasury.

*This internal function transfers the platform fee to the treasury address.*


```solidity
function _sendPlatformFee(address _paymentToken, uint256 _feeAmount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paymentToken`|`address`|Address of the payment token for the fee.|
|`_feeAmount`|`uint256`|Amount of the fee to be transferred.|


### _isValidSignature

Internal function to validate the signature of the provided data.

*Verifies if the signature is from the msg.sender, which can be an externally owned account (EOA) or a
contract implementing ERC-1271.*


```solidity
function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_hash`|`bytes32`|The hash of the data that was signed.|
|`_signature`|`bytes`|The signature byte array associated with the hash.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the signature is valid, false otherwise.|


