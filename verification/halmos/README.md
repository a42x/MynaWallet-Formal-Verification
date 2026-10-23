# Halmos

Halmos uses the shared Foundry project in `verification/solidity`.

```bash
./scripts/verify halmos
```

The initial symbolic property checks the actual inherited `_hashGuardianApproval` implementation for all `bytes16`, `address`, `bytes32`, and `uint256` inputs. The expected value is the canonical chain-id-less ABI encoding.

Always inspect the Halmos log for path bounds, loop bounds, unsupported operations, and solver timeouts.
