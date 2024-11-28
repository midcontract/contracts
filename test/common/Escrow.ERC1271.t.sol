// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { ERC1271WalletMock, ERC1271MaliciousMock } from "@openzeppelin/mocks/ERC1271WalletMock.sol";
import { SignatureChecker, IERC1271 } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";
import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowMilestone, IEscrowMilestone } from "src/EscrowMilestone.sol";
import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { ERC1271, ECDSA } from "src/common/ERC1271.sol";

contract EscrowERC1271UnitTest is Test {
    using ECDSA for bytes32;
    using ECDSA for bytes;

    EscrowFixedPrice escrow;
    EscrowMilestone escrowMilestone;
    EscrowHourly escrowHourly;
    ERC1271WalletMock wallet;
    ERC1271MaliciousMock malicious;

    address signerPublicKey;
    uint256 signerPrivateKey;
    address otherPublicKey;
    uint256 otherPrivateKey;

    bytes private signature;
    bytes32 private constant TEST_MESSAGE = keccak256(abi.encodePacked("Escrow"));
    bytes32 private constant WRONG_MESSAGE = keccak256(abi.encodePacked("Nope"));

    function setUp() public {
        escrow = new EscrowFixedPrice();
        escrowMilestone = new EscrowMilestone();
        escrowHourly = new EscrowHourly();
        (signerPublicKey, signerPrivateKey) = makeAddrAndKey("signer");
        (otherPublicKey, otherPrivateKey) = makeAddrAndKey("other");
        wallet = new ERC1271WalletMock(signerPublicKey);
        malicious = new ERC1271MaliciousMock();
        signature = signMessage(signerPrivateKey, TEST_MESSAGE);
    }

    function signMessage(uint256 privateKey, bytes32 messageHash) internal pure returns (bytes memory) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function externalRecover(bytes32 hash, bytes calldata signature_) external view returns (address) {
        return ECDSA.recover(hash, signature_);
    }

    function runRecoveryTest(bytes32 message, bytes memory signature_) private view returns (bool) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(message);
        address recoveredSigner = this.externalRecover(ethSignedHash, signature_);
        (recoveredSigner);
        return escrow.isValidSignature(message, signature_) == 0x1626ba7e;
    }

    /// EscrowFixedPrice ///

    function test_signerAndSignature_EOAMatching_escrowFixedPrice() public {
        vm.startPrank(signerPublicKey);
        assertTrue(runRecoveryTest(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_EOA_escrowFixedPrice() public view {
        assertFalse(runRecoveryTest(TEST_MESSAGE, signMessage(otherPrivateKey, TEST_MESSAGE)));
    }

    function test_invalidSignature_EOA_escrowFixedPrice() public {
        vm.startPrank(signerPublicKey);
        assertFalse(runRecoveryTest(WRONG_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_signerAndSignature_WalletMatching_escrowFixedPrice() public {
        vm.startPrank(address(wallet));
        assertTrue(runRecoveryTest(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_Wallet_escrowFixedPrice() public {
        vm.startPrank(address(escrow));
        assertFalse(runRecoveryTest(TEST_MESSAGE, signMessage(otherPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSignature_Wallet_escrowFixedPrice() public {
        vm.startPrank(address(wallet));
        assertFalse(runRecoveryTest(WRONG_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_MaliciousWallet_escrowFixedPrice() public {
        vm.startPrank(address(malicious));
        assertFalse(runRecoveryTest(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    /// EscrowMilestone ///

    function runRecoveryTestMilestone(bytes32 message, bytes memory signature_) private view returns (bool) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(message);
        address recoveredSignerMilestone = this.externalRecover(ethSignedHash, signature_);
        (recoveredSignerMilestone);
        return escrowMilestone.isValidSignature(message, signature_) == 0x1626ba7e;
    }

    function test_signerAndSignature_EOAMatching_escrowMilestone() public {
        vm.startPrank(signerPublicKey);
        assertTrue(runRecoveryTestMilestone(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_EOA_escrowMilestone() public view {
        assertFalse(runRecoveryTestMilestone(TEST_MESSAGE, signMessage(otherPrivateKey, TEST_MESSAGE)));
    }

    function test_invalidSignature_EOA_escrowMilestone() public {
        vm.startPrank(signerPublicKey);
        assertFalse(runRecoveryTestMilestone(WRONG_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_signerAndSignature_WalletMatching_escrowMilestone() public {
        vm.startPrank(address(wallet));
        assertTrue(runRecoveryTestMilestone(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_Wallet_escrowMilestone() public {
        vm.startPrank(address(escrow));
        assertFalse(runRecoveryTestMilestone(TEST_MESSAGE, signMessage(otherPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSignature_Wallet_escrowMilestone() public {
        vm.startPrank(address(wallet));
        assertFalse(runRecoveryTestMilestone(WRONG_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_MaliciousWallet_escrowMilestone() public {
        vm.startPrank(address(malicious));
        assertFalse(runRecoveryTestMilestone(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    /// EscrowHourly ///

    function runRecoveryTestHourly(bytes32 message, bytes memory signature_) private view returns (bool) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(message);
        address recoveredSignerHourly = this.externalRecover(ethSignedHash, signature_);
        (recoveredSignerHourly);
        return escrowHourly.isValidSignature(message, signature_) == 0x1626ba7e;
    }

    function test_signerAndSignature_EOAMatching_escrowHourly() public {
        vm.startPrank(signerPublicKey);
        assertTrue(runRecoveryTestHourly(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_EOA_escrowHourly() public view {
        assertFalse(runRecoveryTestHourly(TEST_MESSAGE, signMessage(otherPrivateKey, TEST_MESSAGE)));
    }

    function test_invalidSignature_EOA_escrowHourly() public {
        vm.startPrank(signerPublicKey);
        assertFalse(runRecoveryTestHourly(WRONG_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_signerAndSignature_WalletMatching_escrowHourly() public {
        vm.startPrank(address(wallet));
        assertTrue(runRecoveryTestHourly(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_Wallet_escrowHourly() public {
        vm.startPrank(address(escrow));
        assertFalse(runRecoveryTestHourly(TEST_MESSAGE, signMessage(otherPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSignature_Wallet_escrowHourly() public {
        vm.startPrank(address(wallet));
        assertFalse(runRecoveryTestHourly(WRONG_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }

    function test_invalidSigner_MaliciousWallet_escrowHourly() public {
        vm.startPrank(address(malicious));
        assertFalse(runRecoveryTestHourly(TEST_MESSAGE, signMessage(signerPrivateKey, TEST_MESSAGE)));
        vm.stopPrank();
    }
}
