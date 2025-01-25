# EscrowHourly
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/EscrowHourly.sol)

**Inherits:**
[IEscrowHourly](/src/interfaces/IEscrowHourly.sol/interface.IEscrowHourly.md), [ERC1271](/src/common/ERC1271.sol/abstract.ERC1271.md)

Manages the creation and addition of multiple weekly bills to escrow contracts.


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


### initialized
*Indicates that the contract has been initialized.*


```solidity
bool public initialized;
```


### contractDetails
*Maps from contract ID to its detailed configuration.*


```solidity
mapping(uint256 contractId => ContractDetails) public contractDetails;
```


### weeklyEntries
*Maps a contract ID to an array of `WeeklyEntry` structures representing billing cycles.*


```solidity
mapping(uint256 contractId => WeeklyEntry[] weekIds) public weeklyEntries;
```


### previousStatuses
*Maps each contract ID to its previous status before the return request.*


```solidity
mapping(uint256 contractId => Enums.Status) public previousStatuses;
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

Creates or updates a week's deposit for a new or existing contract.

*This function handles the initialization or update of a week's deposit in a single transaction.
If a new contract ID is provided, a new contract is initialized; otherwise, it adds to an existing
contract.*


```solidity
function deposit(DepositRequest calldata _deposit) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_deposit`|`DepositRequest`|Details for deposit and initial week settings.|


### approve

Approves a deposit by the client.

*This function allows the client to approve a deposit, specifying the amount to approve.*


```solidity
function approve(uint256 _contractId, uint256 _weekId, uint256 _amountApprove, address _receiver) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit to be approved.|
|`_weekId`|`uint256`|ID of the week within the contract to be approved.|
|`_amountApprove`|`uint256`|Amount to approve for the deposit.|
|`_receiver`|`address`|Address of the contractor receiving the approved amount.|


### adminApprove

Approves an existing deposit or creates a new week for approval by the admin.

*This function handles both regular approval within existing weeks and admin-triggered approvals that may
need to create a new week.*


```solidity
function adminApprove(
    uint256 _contractId,
    uint256 _weekId,
    uint256 _amountApprove,
    address _receiver,
    bool _initializeNewWeek
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract for which the approval is happening.|
|`_weekId`|`uint256`|ID of the week within the contract to be approved, or creates a new one if it does not exist.|
|`_amountApprove`|`uint256`|Amount to approve or initialize the week with.|
|`_receiver`|`address`|Address of the contractor receiving the approved amount.|
|`_initializeNewWeek`|`bool`|If true, will initialize a new week if the specified weekId doesn't exist.|


### refill

Refills the prepayment or a specific week's deposit with an additional amount.

*Allows adding additional funds either to the contract's prepayment or to a specific week's payment amount.*


```solidity
function refill(uint256 _contractId, uint256 _weekId, uint256 _amount, Enums.RefillType _type) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract for which the refill is done.|
|`_weekId`|`uint256`|ID of the week within the contract to be refilled, only used if _type is WeekPayment.|
|`_amount`|`uint256`|The additional amount to be added.|
|`_type`|`Enums.RefillType`|The type of refill, either prepayment or week payment.|


### claim

Claims the approved amount by the contractor.

*This function allows the contractor to claim the approved amount from the deposit.*


```solidity
function claim(uint256 _contractId, uint256 _weekId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit from which to claim funds.|
|`_weekId`|`uint256`|ID of the week within the contract to be claimed.|


### claimAll

Allows the contractor to claim for multiple weeks in a specified range if those weeks are approved.

*This function is designed to prevent running out of gas when claiming multiple weeks by limiting the range.*


```solidity
function claimAll(uint256 _contractId, uint256 _startWeekId, uint256 _endWeekId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract for which the claim is made.|
|`_startWeekId`|`uint256`|Starting week ID from which to begin claims.|
|`_endWeekId`|`uint256`|Ending week ID until which claims are made.|


### withdraw

Withdraws funds from a contract under specific conditions.

*Withdraws from the contract's prepayment amount when certain conditions about the contract's
overall status are met.*


```solidity
function withdraw(uint256 _contractId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit from which funds are to be withdrawn.|


### requestReturn

Requests the return of funds by the client for a specific contract.

*The contract must be in an eligible state to request a return (not in disputed or already returned status).*


```solidity
function requestReturn(uint256 _contractId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit for which the return is requested.|


### approveReturn

Approves the return of funds, which can be called by the contractor or platform admin.

*This changes the status of the deposit to allow the client to withdraw their funds.*


```solidity
function approveReturn(uint256 _contractId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit for which the return is approved.|


### cancelReturn

Cancels a previously requested return and resets the deposit's status to the previous one.

*Reverts the status from RETURN_REQUESTED to the previous status stored in `previousStatuses`.*


```solidity
function cancelReturn(uint256 _contractId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The unique identifier of the deposit for which the return is being cancelled.|


### createDispute

Creates a dispute over a specific contract.

*Initiates a dispute status for a contract that can be activated by the client or contractor
when they disagree on the previously submitted work.*


```solidity
function createDispute(uint256 _contractId, uint256 _weekId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract where the dispute occurred.|
|`_weekId`|`uint256`|ID of the contract where the dispute occurred. This function can only be called if the contract status is either RETURN_REQUESTED or SUBMITTED.|


### resolveDispute

Resolves a dispute over a specific contract.

*Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
Admin intervention is required to resolve disputes to ensure fairness.*


```solidity
function resolveDispute(
    uint256 _contractId,
    uint256 _weekId,
    Enums.Winner _winner,
    uint256 _clientAmount,
    uint256 _contractorAmount
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the contract where the dispute occurred.|
|`_weekId`|`uint256`|ID of the contract where the dispute occurred.|
|`_winner`|`Enums.Winner`|Specifies who the winner is: Client, Contractor, or Split.|
|`_clientAmount`|`uint256`|Amount to be allocated to the client if Split or Client wins.|
|`_contractorAmount`|`uint256`|Amount to be allocated to the contractor if Split or Contractor wins. This function ensures that the total resolution amounts do not exceed the deposited amount and adjusts the status of the contract based on the dispute outcome.|


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
function transferContractorOwnership(uint256 _contractId, address _newAccount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
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


### contractExists

Checks if a given contract ID exists.


```solidity
function contractExists(uint256 _contractId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The contract ID to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the contract exists, false otherwise.|


### getWeeksCount

Retrieves the number of weeks for a given contract ID.


```solidity
function getWeeksCount(uint256 _contractId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The contract ID for which to retrieve the week count.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of weeks associated with the given contract ID.|


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


### _verifyIfAllWeeksCompleted

*Internal function to check if all weeks within a contract are completed.*


```solidity
function _verifyIfAllWeeksCompleted(uint256 _contractId) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The ID of the contract to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if all weeks are completed, false otherwise.|


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


### _validateDepositAuthorization

Validates deposit fields against admin-signed approval.


```solidity
function _validateDepositAuthorization(DepositRequest calldata _deposit) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_deposit`|`DepositRequest`|The deposit details including signature and expiration.|


