// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RecoveryHashHarness} from "../src/RecoveryHashHarness.sol";

contract RecoveryHashProperties is Test {
    RecoveryHashHarness internal harness;

    function setUp() public {
        harness = new RecoveryHashHarness();
    }

    function test_hashMatchesCanonicalEncoding(
        bytes16 requestId,
        address account,
        bytes32 qx,
        bytes32 qy,
        uint256 deadline
    ) public view {
        bytes32 expected =
            keccak256(abi.encode(harness.GUARDIAN_APPROVAL_TYPEHASH(), requestId, account, qx, qy, deadline));

        assertEq(harness.exposedHashGuardianApproval(requestId, account, qx, qy, deadline), expected);
    }
}
