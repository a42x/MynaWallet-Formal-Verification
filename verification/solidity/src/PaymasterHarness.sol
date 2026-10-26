// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.26;

import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "@account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";

import {MynaWalletPaymaster} from "mynawallet/src/core/MynaWalletPaymaster.sol";

/// @dev Kontrol harness for MynaWalletPaymaster. Exposes the internal
/// ERC-4337 entry points ("api surface") so proofs can exercise them without
/// the onlyEntryPoint guard, which is out of scope for these properties.
contract PaymasterHarness is MynaWalletPaymaster {
    constructor(IEntryPoint entryPoint) MynaWalletPaymaster(entryPoint) {}

    /// @dev Bypasses BasePaymaster._requireFromEntryPoint; everything else is
    /// the production _validatePaymasterUserOp body.
    function validateDecision(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        returns (bytes memory context, uint256 validationData)
    {
        return _validatePaymasterUserOp(userOp, userOpHash, 0);
    }

    function exposedHashDecision(PaymasterDecision memory decision) external pure returns (bytes32) {
        return _hashDecision(decision);
    }

    function exposedPostOp(IPaymaster.PostOpMode mode, bytes calldata context, uint256 actualGasCost) external {
        _postOp(mode, context, actualGasCost, 0);
    }

    function exposedPostOpModeToString(IPaymaster.PostOpMode mode) external pure returns (string memory) {
        return _postOpModeToString(mode);
    }
}