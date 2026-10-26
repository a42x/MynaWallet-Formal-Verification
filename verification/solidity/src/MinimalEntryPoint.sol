// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.26;

/// @dev Minimal stand-in for the ERC-4337 EntryPoint. BasePaymaster only
/// inspects the entry point address through ERC-165 in its constructor and the
/// proofs below never route calls through the entry point, so a single always
/// true supportsInterface is sufficient.
contract MinimalEntryPoint {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}