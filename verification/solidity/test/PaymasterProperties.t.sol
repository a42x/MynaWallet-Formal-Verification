// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {_packValidationData} from "@account-abstraction/core/Helpers.sol";
import {IPaymaster} from "@account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";

import {MynaWalletPaymaster} from "mynawallet/src/core/MynaWalletPaymaster.sol";
import {Errors} from "mynawallet/src/libraries/Errors.sol";

import {MinimalEntryPoint} from "../src/MinimalEntryPoint.sol";
import {PaymasterHarness} from "../src/PaymasterHarness.sol";

/// @dev Kontrol proof suite for the gas-sponsor (verifying paymaster) API.
/// Bounded claims: symbolic fields are named per test; every control-flow
/// property outside those fields uses concrete constants.
contract PaymasterProperties is Test {
    PaymasterHarness internal pm;

    bytes32 internal constant OP_HASH = keccak256("paymaster.proof.userOpHash");
    bytes32 internal constant KID = keccak256("paymaster.proof.kid");
    bytes32 internal constant UNREGISTERED_KID = keccak256("paymaster.proof.unregistered-kid");
    bytes32 internal constant PAYER_ID = keccak256("paymaster.proof.payer");
    bytes32 internal constant POLICY_ID = keccak256("paymaster.proof.policy");

    uint256 internal constant SIGNER_KEY = 0xA11CE;
    uint64 internal constant TS = 1_700_000_000;

    function setUp() public {
        IEntryPoint entryPoint = IEntryPoint(address(new MinimalEntryPoint()));
        pm = new PaymasterHarness(entryPoint);
        pm.setSigner(KID, vm.addr(SIGNER_KEY));
        vm.warp(TS);
    }

    // ------------------------------------------------------------------
    // PM-KONTROL-001: canonical decision digest
    // ------------------------------------------------------------------
    // Symbolic: all PaymasterDecision fields; no signature path is executed.
    function test_decisionDigestMatchesCanonicalEncoding(
        bytes32 userOpHash,
        uint64 validUntil,
        uint64 validAfter,
        uint64 nonce,
        bytes32 kid,
        bytes32 payerId,
        bytes32 policyId
    ) public view {
        MynaWalletPaymaster.PaymasterDecision memory decision = MynaWalletPaymaster.PaymasterDecision({
            userOpHash: userOpHash,
            validUntil: validUntil,
            validAfter: validAfter,
            nonce: nonce,
            kid: kid,
            payerId: payerId,
            policyId: policyId
        });

        bytes32 expected = keccak256(
            abi.encode(pm.PAYMASTER_DECISION_TYPEHASH(), userOpHash, validUntil, validAfter, nonce, kid, payerId, policyId)
        );

        assertEq(pm.exposedHashDecision(decision), expected);
    }

    // ------------------------------------------------------------------
    // PM-KONTROL-002: TTL window is enforced
    // ------------------------------------------------------------------
    // Symbolic: validUntil; concrete: everything else. The revert fires
    // before any signature evaluation, so a dummy signature is harmless.
    function test_expiredDecisionReverts(uint64 validUntil) public {
        vm.assume(validUntil != 0);
        vm.assume(validUntil < block.timestamp);

        PackedUserOperation memory userOp = _userOp(_decision(OP_HASH, KID, validUntil, 0, 7), _dummySignature(), 0);

        vm.expectRevert(Errors.PAYMASTER_DECISION_EXPIRED.selector);
        pm.validateDecision(userOp, OP_HASH);
    }

    // Symbolic: validAfter; concrete: everything else.
    function test_notYetValidDecisionReverts(uint64 validAfter) public {
        vm.assume(validAfter != 0);
        vm.assume(validAfter > block.timestamp);

        PackedUserOperation memory userOp = _userOp(_decision(OP_HASH, KID, 0, validAfter, 7), _dummySignature(), 0);

        vm.expectRevert(Errors.PAYMASTER_DECISION_NOT_YET_VALID.selector);
        pm.validateDecision(userOp, OP_HASH);
    }

    // Concrete: window bounds exceed uint48 range but sit after the TTL checks.
    function test_windowOverflowReverts() public {
        MynaWalletPaymaster.PaymasterDecision memory decision =
            _decision(OP_HASH, KID, uint64(type(uint48).max) + 1, 0, 7);

        PackedUserOperation memory userOp = _userOp(decision, _dummySignature(), 0);

        vm.expectRevert(Errors.PAYMASTER_TIME_WINDOW_OVERFLOW.selector);
        pm.validateDecision(userOp, OP_HASH);
    }


    // ------------------------------------------------------------------
    // PM-KONTROL-004: replay protection
    // ------------------------------------------------------------------
    // Concrete bounded run: sponsor decision validates once; the same
    // (userOpHash, nonce) is rejected afterward regardless of mode byte.
    function test_usedDecisionCannotValidateAgain() public {
        MynaWalletPaymaster.PaymasterDecision memory decision = _decision(OP_HASH, KID, TS + 100, 0, 7);
        PackedUserOperation memory sponsorOp = _userOp(decision, _signDecision(decision), 0);

        (bytes memory context, uint256 validationData) = pm.validateDecision(sponsorOp, OP_HASH);
        assertTrue(keccak256(context) == keccak256(abi.encode(PAYER_ID, POLICY_ID, OP_HASH)));
        assertEq(validationData, _packValidationData(false, uint48(TS + 100), 0));
        assertTrue(used(decision));

        vm.expectRevert(Errors.PAYMASTER_REPLAY_NONCE.selector);
        pm.validateDecision(sponsorOp, OP_HASH);

        // Same usage key under the USER mode byte is also consumed.
        PackedUserOperation memory userModeOp = _userOp(decision, _signDecision(decision), 1);
        vm.expectRevert(Errors.PAYMASTER_REPLAY_NONCE.selector);
        pm.validateDecision(userModeOp, OP_HASH);
    }

    // ------------------------------------------------------------------
    // PM-KONTROL-005: unknown signer kid is rejected
    // ------------------------------------------------------------------
    // Concrete: unregistered kid; rejection happens before signature checks.
    function test_unknownSignerKidReverts() public {
        MynaWalletPaymaster.PaymasterDecision memory decision = _decision(OP_HASH, UNREGISTERED_KID, TS + 100, 0, 7);
        PackedUserOperation memory userOp = _userOp(decision, _signDecision(decision), 0);

        vm.expectRevert(Errors.PAYMASTER_UNKNOWN_SIGNER.selector);
        pm.validateDecision(userOp, OP_HASH);
    }

    // ------------------------------------------------------------------
    // PM-KONTROL-006: encoding gates
    // ------------------------------------------------------------------
    // Symbolic: version byte, bounded to any value except 0x01.
    function test_unsupportedVersionReverts(uint8 version) public {
        vm.assume(version != 1);

        PackedUserOperation memory userOp = _packedUserOpBytes(
            abi.encodePacked(bytes1(version), bytes1(0), abi.encode(_decision(OP_HASH, KID, TS + 100, 0, 7), _dummySignature()))
        );

        vm.expectRevert(Errors.PAYMASTER_INVALID_VERSION.selector);
        pm.validateDecision(userOp, OP_HASH);
    }

    // Symbolic: mode byte, bounded to values above 1 (HYBRID reserved).
    function test_unsupportedModeReverts(uint8 mode) public {
        vm.assume(mode > 1);

        PackedUserOperation memory userOp = _packedUserOpBytes(
            abi.encodePacked(bytes1(0x01), bytes1(mode), abi.encode(_decision(OP_HASH, KID, TS + 100, 0, 7), _dummySignature()))
        );

        vm.expectRevert(Errors.PAYMASTER_INVALID_MODE.selector);
        pm.validateDecision(userOp, OP_HASH);
    }

    // Concrete: paymasterAndData shorter than the 2-byte header reverts.
    function test_malformedPaymasterDataReverts() public {
        PackedUserOperation memory userOp = _packedUserOpBytes(hex"01");

        vm.expectRevert(Errors.PAYMASTER_MALFORMED_DATA.selector);
        pm.validateDecision(userOp, OP_HASH);
    }

    // ------------------------------------------------------------------
    // PM-KONTROL-007: modes behave identically on the happy path
    // ------------------------------------------------------------------
    // Concrete bounded run: each mode validates a fresh (userOpHash, nonce)
    // with identical context and packed validationData derived from the TTL.
    function test_sponsorModeDecisionValidates() public {
        MynaWalletPaymaster.PaymasterDecision memory decision = _decision(OP_HASH, KID, TS + 100, 0, 7);

        (bytes memory context, uint256 validationData) =
            pm.validateDecision(_userOp(decision, _signDecision(decision), 0), OP_HASH);
        assertTrue(keccak256(context) == keccak256(abi.encode(PAYER_ID, POLICY_ID, OP_HASH)));
        assertEq(validationData, _packValidationData(false, uint48(TS + 100), 0));
        assertTrue(pm.used(keccak256(abi.encode(OP_HASH, uint64(7)))));
    }

    function test_userModeDecisionValidates() public {
        MynaWalletPaymaster.PaymasterDecision memory decision = _decision(OP_HASH, KID, TS + 100, 0, 8);

        (bytes memory context, uint256 validationData) =
            pm.validateDecision(_userOp(decision, _signDecision(decision), 1), OP_HASH);
        assertTrue(keccak256(context) == keccak256(abi.encode(PAYER_ID, POLICY_ID, OP_HASH)));
        assertEq(validationData, _packValidationData(false, uint48(TS + 100), 0));
        assertTrue(pm.used(keccak256(abi.encode(OP_HASH, uint64(8)))));
    }

    // ------------------------------------------------------------------
    // PM-KONTROL-008: postOp audit
    // ------------------------------------------------------------------
    // Concrete bounded run: the audit event decodes the sponsor context
    // exactly and names the PostOpMode.
    function test_postOpEmitsAuditEvent() public {
        vm.expectEmit(true, true, true, true);
        emit MynaWalletPaymaster.PostOpAudit("opSucceeded", PAYER_ID, POLICY_ID, OP_HASH, 12_345);
        pm.exposedPostOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(PAYER_ID, POLICY_ID, OP_HASH), 12_345);

        vm.expectEmit(true, true, true, true);
        emit MynaWalletPaymaster.PostOpAudit("postOpReverted", PAYER_ID, POLICY_ID, OP_HASH, 1);
        pm.exposedPostOp(IPaymaster.PostOpMode.postOpReverted, abi.encode(PAYER_ID, POLICY_ID, OP_HASH), 1);
    }

    function test_postOpModeStringMatchesAuditLabel() public view {
        assertTrue(
            keccak256(bytes(pm.exposedPostOpModeToString(IPaymaster.PostOpMode.opSucceeded)))
                == keccak256(bytes("opSucceeded"))
        );
        assertTrue(
            keccak256(bytes(pm.exposedPostOpModeToString(IPaymaster.PostOpMode.opReverted)))
                == keccak256(bytes("opReverted"))
        );
        assertTrue(
            keccak256(bytes(pm.exposedPostOpModeToString(IPaymaster.PostOpMode.postOpReverted)))
                == keccak256(bytes("postOpReverted"))
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _decision(bytes32 userOpHash, bytes32 kid, uint64 validUntil, uint64 validAfter, uint64 nonce)
        internal
        pure
        returns (MynaWalletPaymaster.PaymasterDecision memory)
    {
        return MynaWalletPaymaster.PaymasterDecision({
            userOpHash: userOpHash,
            validUntil: validUntil,
            validAfter: validAfter,
            nonce: nonce,
            kid: kid,
            payerId: PAYER_ID,
            policyId: POLICY_ID
        });
    }

    function _signDecision(MynaWalletPaymaster.PaymasterDecision memory decision)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", pm.domainSeparator(), pm.exposedHashDecision(decision)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _dummySignature() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(0xC0FFEE)), bytes32(uint256(0xBADF00D)), uint8(27));
    }

    function _userOp(MynaWalletPaymaster.PaymasterDecision memory decision, bytes memory signature, uint8 mode)
        internal
        view
        returns (PackedUserOperation memory)
    {
        return _packedUserOpBytes(abi.encodePacked(bytes1(0x01), bytes1(mode), abi.encode(decision, signature)));
    }

    /// @dev paymasterAndData layout: paymaster address (20) + verification
    /// gas limit (16) + postOp gas limit (16) = PAYMASTER_DATA_OFFSET (52),
    /// then the version byte at offset 52.
    function _packedUserOpBytes(bytes memory paymasterData) internal view returns (PackedUserOperation memory) {
        bytes memory full =
            abi.encodePacked(address(pm), bytes16(uint128(160_000)), bytes16(uint128(80_000)), paymasterData);
        return PackedUserOperation({
            sender: address(0x51CE),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: full,
            signature: ""
        });
    }

    function used(MynaWalletPaymaster.PaymasterDecision memory decision) internal view returns (bool) {
        return pm.used(keccak256(abi.encode(decision.userOpHash, decision.nonce)));
    }
}