// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.26;

import {PasskeyRecoveryExecutor} from "mynawallet/src/modules/executors/PasskeyRecoveryExecutor.sol";

contract RecoveryHashHarness is PasskeyRecoveryExecutor {
    function exposedHashGuardianApproval(
        bytes16 recoveryRequestId,
        address account,
        bytes32 qx,
        bytes32 qy,
        uint256 deadline
    ) external pure returns (bytes32) {
        return _hashGuardianApproval(recoveryRequestId, account, qx, qy, deadline);
    }
}
