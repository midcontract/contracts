// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {ERC1271WalletMock, ERC1271MaliciousMock} from "@openzeppelin/mocks/ERC1271WalletMock.sol";
import {SignatureChecker, IERC1271} from "@openzeppelin/utils/cryptography/SignatureChecker.sol";
import {EscrowFixedPrice, IEscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowMilestone, IEscrowMilestone} from "src/EscrowMilestone.sol";
import {EscrowHourly, IEscrowHourly} from "src/EscrowHourly.sol";
import {ERC1271, ECDSA} from "src/libs/ERC1271.sol";

contract EscrowERC1271UnitTest is Test {
    using ECDSA for bytes32;

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
    bytes32 private constant TEST_MESSAGE = keccak256(abi.encodePacked("OpenZeppelin"));
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

    function signMessage(uint256 privateKey, bytes32 messageHash) internal returns (bytes memory) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(hash);
    }

    /// EscrowFixedPrice ///

    function test_signerAndSignature_EOAMatching_escrowFixedPrice() public {
        vm.startPrank(signerPublicKey);
        signature = signMessage(signerPrivateKey, TEST_MESSAGE);

        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertEq(recoveredSigner, signerPublicKey, "Recovered signer should match the signer public key");
        bool isValid = escrow.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertTrue(isValid, "EOA matching signer and signature should be valid");
    }

    function test_invalidSigner_EOA_escrowFixedPrice() public {
        vm.startPrank(otherPublicKey);
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertNotEq(recoveredSigner, otherPublicKey, "Recovered signer should not match the other public key");
        bool isValid = escrow.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "EOA invalid signer should not be valid");
    }

    function test_invalidSignature_EOA_escrowFixedPrice() public {
        vm.startPrank(signerPublicKey);
        bytes32 ethSignedHash = toEthSignedMessageHash(WRONG_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertNotEq(
            recoveredSigner,
            signerPublicKey,
            "Recovered signer should not match the signer public key for wrong message"
        );
        bool isValid = escrow.isValidSignature(WRONG_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "EOA invalid signature should not be valid");
    }

    function test_signerAndSignature_WalletMatching_escrowFixedPrice() public {
        vm.startPrank(address(wallet));

        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrow.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;

        assertTrue(isValid, "Wallet matching signer and signature should be valid");
    }

    function test_invalidSigner_Wallet_escrowFixedPrice() public {
        vm.startPrank(address(escrow));
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrow.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Wallet invalid signer should not be valid");
    }

    function test_invalidSignature_Wallet_escrowFixedPrice() public {
        vm.startPrank(address(wallet));
        bytes32 ethSignedHash = toEthSignedMessageHash(WRONG_MESSAGE);
        bool isValid = escrow.isValidSignature(WRONG_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Wallet invalid signature should not be valid");
    }

    function test_invalidSigner_MaliciousWallet_escrowFixedPrice() public {
        vm.startPrank(address(malicious));
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrow.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Malicious wallet should not be valid");
    }

    /// EscrowMilestone ///

    function test_signerAndSignature_EOAMatching_escrowMilestone() public {
        vm.startPrank(signerPublicKey);
        signature = signMessage(signerPrivateKey, TEST_MESSAGE);

        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertEq(recoveredSigner, signerPublicKey, "Recovered signer should match the signer public key");
        bool isValid = escrowMilestone.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertTrue(isValid, "EOA matching signer and signature should be valid");
    }

    function test_invalidSigner_EOA_escrowMilestone() public {
        vm.startPrank(otherPublicKey);
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertNotEq(recoveredSigner, otherPublicKey, "Recovered signer should not match the other public key");
        bool isValid = escrowMilestone.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "EOA invalid signer should not be valid");
    }

    function test_invalidSignature_EOA_escrowMilestone() public {
        vm.startPrank(signerPublicKey);
        bytes32 ethSignedHash = toEthSignedMessageHash(WRONG_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertNotEq(
            recoveredSigner,
            signerPublicKey,
            "Recovered signer should not match the signer public key for wrong message"
        );
        bool isValid = escrowMilestone.isValidSignature(WRONG_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "EOA invalid signature should not be valid");
    }

    function test_signerAndSignature_WalletMatching_escrowMilestone() public {
        vm.startPrank(address(wallet));

        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrowMilestone.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;

        assertTrue(isValid, "Wallet matching signer and signature should be valid");
    }

    function test_invalidSigner_Wallet_escrowMilestone() public {
        vm.startPrank(address(escrowMilestone));
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrowMilestone.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Wallet invalid signer should not be valid");
    }

    function test_invalidSignature_Wallet_escrowMilestone() public {
        vm.startPrank(address(wallet));
        bytes32 ethSignedHash = toEthSignedMessageHash(WRONG_MESSAGE);
        bool isValid = escrowMilestone.isValidSignature(WRONG_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Wallet invalid signature should not be valid");
    }

    function test_invalidSigner_MaliciousWallet_escrowMilestone() public {
        vm.startPrank(address(malicious));
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrowMilestone.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Malicious wallet should not be valid");
    }

    /// EscrowHourly ///

    function test_signerAndSignature_EOAMatching_escrowHourly() public {
        vm.startPrank(signerPublicKey);
        signature = signMessage(signerPrivateKey, TEST_MESSAGE);

        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertEq(recoveredSigner, signerPublicKey, "Recovered signer should match the signer public key");
        bool isValid = escrowHourly.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertTrue(isValid, "EOA matching signer and signature should be valid");
    }

    function test_invalidSigner_EOA_escrowHourly() public {
        vm.startPrank(otherPublicKey);
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertNotEq(recoveredSigner, otherPublicKey, "Recovered signer should not match the other public key");
        bool isValid = escrowHourly.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "EOA invalid signer should not be valid");
    }

    function test_invalidSignature_EOA_escrowHourly() public {
        vm.startPrank(signerPublicKey);
        bytes32 ethSignedHash = toEthSignedMessageHash(WRONG_MESSAGE);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);

        assertNotEq(
            recoveredSigner,
            signerPublicKey,
            "Recovered signer should not match the signer public key for wrong message"
        );
        bool isValid = escrowHourly.isValidSignature(WRONG_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "EOA invalid signature should not be valid");
    }

    function test_signerAndSignature_WalletMatching_escrowHourly() public {
        vm.startPrank(address(wallet));

        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrowHourly.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;

        assertTrue(isValid, "Wallet matching signer and signature should be valid");
    }

    function test_invalidSigner_Wallet_escrowHourly() public {
        vm.startPrank(address(escrowHourly));
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrowHourly.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Wallet invalid signer should not be valid");
    }

    function test_invalidSignature_Wallet_escrowHourly() public {
        vm.startPrank(address(wallet));
        bytes32 ethSignedHash = toEthSignedMessageHash(WRONG_MESSAGE);
        bool isValid = escrowHourly.isValidSignature(WRONG_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Wallet invalid signature should not be valid");
    }

    function test_invalidSigner_MaliciousWallet_escrowHourly() public {
        vm.startPrank(address(malicious));
        bytes32 ethSignedHash = toEthSignedMessageHash(TEST_MESSAGE);
        bool isValid = escrowHourly.isValidSignature(TEST_MESSAGE, signature) == 0x1626ba7e;
        assertFalse(isValid, "Malicious wallet should not be valid");
    }
}
