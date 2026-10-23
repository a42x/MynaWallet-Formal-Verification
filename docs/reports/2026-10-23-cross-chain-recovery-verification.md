# Cross-chain recovery formal verification report

## 1. Executive summary

MynaWallet cross-chain recovery implementation was checked at the protocol-model, Solidity symbolic-execution, EVM-semantics, specification-compilation, and integration-test layers.

Within the executed scope, every runnable verification stage passed. No invariant violation, symbolic counterexample, assertion failure, vacuous Kontrol proof, or Foundry test failure was found.

The Certora specification compiled successfully, but the remote Certora Prover job was not submitted because `CERTORAKEY` was not configured. Therefore, this report does **not** claim that the Certora invariant has been proved.

| Stage | Result |
|---|---:|
| Quint typecheck | PASS |
| Quint scenario tests | 5/5 PASS |
| TLC exhaustive finite-state model check | PASS |
| Solidity verification harness build | PASS |
| Halmos symbolic property | 1/1 PASS |
| Certora Solidity/CVL compilation | PASS |
| Certora remote proof | SKIP — `CERTORAKEY` unset |
| Kontrol project build | PASS |
| Kontrol EVM-semantics proof | PASS |
| Target cross-chain Foundry E2E | 11/11 PASS |

Final run totals:

- Failures: **0**
- Skips: **1**
- Executed verification stages: **9 PASS**

## 2. Verified revisions and toolchain

### Source revisions

| Component | Revision |
|---|---|
| Formal-verification harness | `a2e28c58fae5314b95798fe83a43cf962c9d5602` |
| MynaWallet-SC target | `357027d4b7e04ee6fd5cfca913bc1acfd1a30392` |
| Target branch at pinning time | `feat/cross-chain-recovery` |

### Tool versions

| Tool | Version |
|---|---|
| Node.js | `22.22.0` |
| npm | `10.9.4` |
| Python | `3.12.2` |
| uv | `0.6.3` |
| Foundry | `1.5.1-stable` |
| Solidity compiler | `0.8.26` |
| Quint | `0.33.0` |
| Apalache | `0.62.1` |
| Halmos | `0.3.3` |
| Certora CLI | `8.20.2` |
| Kontrol | `1.0.255` |
| Kontrol image | `runtimeverificationinc/kontrol@sha256:858f004144d61b005997f56bb8b7cd15673850286c96e0e5ec0502d9c9a9e204` |

### Reproduction command

```bash
./scripts/bootstrap
./scripts/verify full
```

Local evidence directory:

```text
results/20261023T072453Z-a2e28c5/
```

## 3. Protocol model verification — Quint and TLC

### Model scope

The finite-state model represents two chains and the following behavior:

- independent message delivery to chain A and chain B;
- independent request consumption on each chain;
- duplicate submission/replay rejection;
- pause and unpause behavior;
- guardian/configuration rotation causing stale configuration;
- reconciliation followed by delayed recovery;
- installation of the same requested key after successful execution.

Cryptographic validation is abstracted as configuration validity. Digest construction and compiled EVM behavior are checked separately by Halmos and Kontrol.

### Safety properties

The TLC `safety` invariant combines:

1. each chain executes a request at most once;
2. a consumed request corresponds to exactly one successful execution;
3. execution installs the requested key;
4. the key is not mutated before execution;
5. if both chains execute the request, both converge on the same key.

These cover property IDs `CCR-MODEL-001` through `CCR-MODEL-004` in `verification/properties.yaml`.

### Scenario tests

All five Quint scenarios passed:

| Scenario | Result |
|---|---:|
| `fanoutSuccessTest` | PASS |
| `replayIsRejectedTest` | PASS |
| `staleConfigCausesPartialRecoveryTest` | PASS |
| `reconcileAllowsDelayedRecoveryTest` | PASS |
| `pauseBlocksUntilUnpausedTest` | PASS |

### TLC exhaustive search

```text
793 states generated
144 distinct states found
0 states left on queue
complete state graph depth: 9
No violation found
```

The queue was exhausted, so TLC completed the reachable state graph for the configured finite model. This proves the stated invariant for that model and its finite domains, not for arbitrary real-world chain counts, relayer behavior, or unbounded executions.

## 4. Solidity symbolic verification — Halmos

Property `CCR-HALMOS-001` checks, for symbolic values of all inputs, that the guardian approval hash produced by the implementation equals the canonical chain-id-less encoding:

```solidity
keccak256(
    abi.encode(
        GUARDIAN_APPROVAL_TYPEHASH,
        requestId,
        account,
        qx,
        qy,
        deadline
    )
)
```

Result:

```text
1 symbolic test passed
0 failed
3 explored paths
No bounds applied
```

Verified function:

```text
RecoveryHashSymbolic.check_hashMatchesCanonicalEncoding(
    bytes16,address,bytes32,bytes32,uint256
)
```

No symbolic counterexample was found.

Compiler warnings observed during this stage:

- unused `reason` parameter in a `catch Error` clause;
- unused `oldAdmin` local variable;
- Foundry naming lint for the underscore in the symbolic-test function name.

These warnings did not affect compilation or the property result.

## 5. EVM-semantics verification — Kontrol/KEVM

Property `CCR-KONTROL-001` checks the same canonical hash relation against the compiled contract behavior under KEVM semantics.

### Build

```text
Kontrol project built successfully
Optimization level: O0
```

The official Kontrol `1.0.255` Docker image is pinned by digest. On memory-constrained runners, the LLVM helper and Haskell definition are kompiled sequentially rather than concurrently; the generated definitions and proof target are unchanged.

### Proof

Verified function:

```text
test%RecoveryHashProperties.test_hashMatchesCanonicalEncoding(
    bytes16,address,bytes32,bytes32,uint256
)
```

Result:

```text
Setup: PASS — 4 nodes, 0 pending, 0 failing, 0 vacuous
Property: PASS — 9 nodes, 0 pending
PROOF PASSED
Elapsed proof time: 2m 8s
```

No failing or vacuous proof branch was reported.

## 6. Certora specification status

Property `CCR-CERTORA-001` states:

> Once `consumedRecoveryRequests[requestId]` becomes true, no successful public method can make it false again.

The target contract and CVL specification compiled successfully with Certora CLI `8.20.2` and Solidity `0.8.26`.

```text
PASS certora-compile
SKIP certora — CERTORAKEY is unset
```

The compilation emitted package-remapping warnings because several configured package paths end in `/`. Compilation still completed successfully.

### Important qualification

The monotonicity rule has **not** been proved by the remote Certora Prover in this run. It remains pending until a valid `CERTORAKEY` is supplied and the following command completes:

```bash
CERTORAKEY=... ./scripts/verify certora
```

## 7. Cross-chain Foundry integration tests

The pinned target suite `CrossChainRecoveryE2EFlow.t.sol` passed all 11 tests:

| Test | Result |
|---|---:|
| Different chains accept the same request ID | PASS |
| Same signatures succeed on all chains | PASS |
| Recovery adds the new passkey to the validator | PASS |
| Recovery succeeds through EntryPoint | PASS |
| Same-chain second submission is rejected after consumption | PASS |
| Expired deadline is rejected | PASS |
| Fresh nonce cannot bypass consumed-request defense | PASS |
| Insufficient guardian signatures are rejected | PASS |
| Same-chain EntryPoint nonce replay is rejected | PASS |
| Paused executor rejects recovery | PASS |
| Invalid relayer signature is rejected | PASS |

Suite result:

```text
11 passed
0 failed
0 skipped
```

## 8. Conclusions

The executed checks support the following conclusions for the pinned revision:

- the finite two-chain protocol model enforces at-most-once execution per chain;
- request consumption and execution remain consistent in the model;
- successful executions converge on the same requested key;
- paused and stale-configuration chains do not execute until their blocking condition is removed;
- replay attempts do not create a second execution in the model or E2E tests;
- the guardian approval digest excludes chain-specific data exactly as specified, for symbolic inputs;
- the compiled EVM behavior for the digest agrees with the canonical encoding;
- the EntryPoint recovery path and the tested rejection paths pass in the target Foundry suite.

No counterexample or test failure was found within this scope.

## 9. Remaining gaps and limitations

This work is not a proof of the complete wallet or complete recovery system.

1. **Certora remote proof is pending.** Only compilation and CVL validation passed.
2. **Kontrol currently proves the digest property only.** Full proxy, delegatecall rollback, EIP-7702, EntryPoint state-transition, replay, and cleanup proofs have not yet been implemented in Kontrol.
3. **The Quint model is finite and abstract.** Cryptography, arbitrary chain counts, chain reorgs/finality, relayer compromise, and unbounded liveness are outside the current model.
4. **Eventual delivery is assumed operationally.** There is no current liveness proof that every valid recovery message is eventually delivered and executed.
5. **Guardian/configuration divergence remains an operational risk.** The model demonstrates partial recovery under stale configuration but does not prove an external reconciliation service will restore consistency.
6. **Compiler/lint warnings remain.** They did not invalidate the checks but should be cleaned up separately.

## 10. CI reproduction status

The local full verification run passed as reported above. The GitHub Actions run for commit `a2e28c5` failed before executing verification because the public formal-verification repository could not clone the private `a42x/MynaWallet-SC` submodule using its default `GITHUB_TOKEN`.

This is an infrastructure/authentication failure, not a verification counterexample. CI reproduction requires one of the following:

- a read token for `a42x/MynaWallet-SC` configured as an Actions secret;
- an organization-level reusable credential with access to both repositories; or
- making the pinned target revision externally readable.

Failed workflow run:

```text
https://github.com/a42x/MynaWallet-Formal-Verification/actions/runs/39916003417
```
