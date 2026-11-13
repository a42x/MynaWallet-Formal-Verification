---
title: Gas sponsor model
last_updated: 2026-11-13
tags:
  - formal-verification
  - quint
  - gas-sponsor
---

# Gas sponsor model

## Run the checks

```bash
./scripts/doctor
./scripts/verify gas-model
./scripts/verify gas-findings
```

`gas-model` typechecks the models, runs 31 scenario tests, and checks three
finite-state safety conjunctions with TLC. Each TLC invocation has a five-minute
timeout. `gas-findings` checks three stronger desired properties and currently
exits 1 with three **FAIL** counterexamples. A tool error or timeout is **UNKNOWN**,
not evidence that a property holds. The scenario tests reproduce those failures;
their passing status does not turn the violated properties into PASS.

`quick` includes the new typecheck and scenario tests. `model`, `full`, and the
existing CI model job include all three safety checks. Findings run separately,
like `auth-findings`, so expected counterexamples do not hide new regressions.

## Target and boundaries

The reference is [a42x/api at dd2b9821](https://github.com/a42x/api/tree/dd2b982100960b9dfce9e6f0c02e42a8e450e211),
pinned with inspected paths in `verification/gas-sponsor-source.lock.json`.
It is a separate snapshot from the existing authentication model. No API code,
Solidity submodule, dependency, or tool version is changed.

The actual boundary is API ↔ Pimlico, not API ↔ `MynaWalletPaymaster.sol`:

```text
prepare -> Pimlico requested webhook -> judgment / sponsor pool hold
        -> Pimlico finalized webhook (paymaster data filled, NOT confirmation)
submit  -> nonce preflight -> charge reserve / sponsor quota -> bundler
receipt -> finalized handler or backfill -> settlement
stale reservation + bundler unknown -> sweeper -> release
```

These are **three independent projections**, not a composed end-to-end proof.
They check source-shaped state transitions, not the deployed TypeScript runtime,
PostgreSQL implementation, Pimlico contract, or EVM execution.

| Model | Finite domain | Checked properties |
|---|---|---|
| `GasSponsorPool.qnt` | 2 judgments, 1 pool, initial funds 3, hold 2, at most 2 requested judgments per key | `GAS-POOL-001..004` |
| `GasSponsorCharge.qnt` | 2 judgments interpreted as two chains sharing one identity's balance, initial funds 3, estimate 2, at most 2 reserves per judgment | `GAS-CHARGE-001..005` |
| `GasSponsorQuota.qnt` | 2 judgments across two chains, 1 identity, 1 day, shared/sponsor-A/sponsor-B buckets, fixed limit 1, 2 calldata intents | `GAS-QUOTA-001..004` |

Money is an integer abstraction; known receipt costs are `{0, 1, 2, 4}` and `-1`
means unavailable. The bounds exercise refunds, exact cost, excess cost, and
insufficient headroom. They are not production amounts or limits. TLC explores
the complete reachable graph of these finite domains, not merely a fixed trace
length. `verification/properties.yaml` maps every claimed invariant to its model.

### Assumptions and exclusions

- The webhook verifier, wallet ownership check, signature checks, identity
  resolver, and policy predicate evaluator supply trusted inputs. Their security
  is not proved here. The pool model covers ordinary matched sponsor policies;
  recovery-unpooled and other policy exemptions are excluded.
- Successful row-lock-protected transactions commit atomically. Failed commits
  leave persistent effects unchanged. For charge retroactive settlement, an
  empty `SELECT ... FOR UPDATE` is explicitly **not** a lock on a future insert.
  This models ordinary PostgreSQL READ COMMITTED behavior; a deployment's
  server-level isolation configuration is not checked by this harness.
- Charge `preflight` represents a submit that passed the nonce check before the
  receipt arrived. It may reach the DB reserve later. No fresh post-receipt
  nonce validation is allowed. There is one fixed receipt transaction hash per
  judgment, with different hashes for the two judgments.
- Charge balances start nonnegative and use the chain-agnostic pool. Legacy
  per-chain fallback, non-gas debt, deposits, IAP, chargebacks, and cross-user
  isolation are excluded. Zero-cost charge receipts are observable but the
  positive-cost settlement guard is preserved; eventual zero-cost cleanup is
  not claimed.
- `elapsed` abstracts passing the sweep TTL and scan-eligibility checks. Bundler
  responses are `known`, `unknown`, or `unavailable`; only `unknown` releases.
  No claim connects the abstract TTL to Pimlico signature validity. Backfill
  exhaustion, scheduling fairness, and eventual progress are not verified.
- The pool correlation key and calldata stay fixed across retries. The quota
  projection permits outcome/intent changes before a slot is claimed and policy
  disappearance, but excludes scope/limit changes after a claim, day rollover,
  program quotas, and global/sponsor monetary abuse caps.
- Receipt authenticity, chain finality, calldata encoding, cryptography, and
  currency conversion are assumptions, not model-checked properties.

## Source correspondence

Paths below are relative to `api/src/` in the pinned API snapshot.

| Model actions | Implementation boundary |
|---|---|
| Pool `open`, `judge` | `gas-sponsor/repositories/judgments.repository.ts::reserveJudgment`; `services/judgment-orchestrator.ts::handleRequested`; `services/judgment.service.ts::decideAndCommit` |
| Pool reserve / settlement arithmetic | `gas-sponsor/repositories/pools.repository.ts::reserveBalance/settleReservation` |
| Pool `finalized`, `backfill`, `settle` | `gas-sponsor/services/finalize-orchestrator.ts::handleFinalized`; `jobs/gas-sponsor-receipt-backfill.job.ts`; `gas-sponsor/services/pool-settlement.ts::trySettleOrSkip` |
| Pool/charge `expire`, `sweep` | `jobs/gas-sponsor-reservation-sweeper.job.ts`; `judgments.repository.ts::findStaleReservations`; `charge-ledger.repository.ts::cancelSpend` |
| Charge `prepare`, `preflight`, `submit` | `judgment.service.ts::attemptChargeOrDeny`; `transactions/services/transaction-execution.service.ts`; `gas-sponsor/services/commit-charge-reserve.ts`; `charge-ledger.repository.ts::recordSpendInExecutor` |
| Charge `receipt`, `finalizeSpend`, `beginRetro`, `finishRetro` | `finalize-orchestrator.ts` and the receipt-backfill job; `charge-ledger.repository.ts::finalizeSpend/retroactiveDebitCancelledReserve` |
| Quota `lookup`, `commit` | `gas-sponsor/services/commit-sponsor-slot.service.ts`; `repositories/abuse-counters.repository.ts::tryClaimUserSlot`; `judgments.repository.ts::markSlotFinalized` |

The source's judgment locks serialize duplicate pool reservations and same-key
charge submits. Counter claims and slot stamps share a transaction. Pool
settlement claims and pool balance changes also share a transaction. In contrast,
charge receipt storage is separate from charge-ledger settlement; that gap is
visible in the charge model.

## Counterexamples

These are failures of the stated finite-model properties, not confirmed incidents
or live-deployment exploit reproductions. Production code is intentionally left
unchanged. The traces below are deterministic scenario-test witnesses; TLC may
choose equivalent interleavings or operation names.

### GAS-POOL-CE-001: replay after release has no active hold

```text
open A -> judge A (hold 2) -> finalized A (receipt unavailable)
       -> expire A -> sweep A (unknown, refund 2) -> judge A again
```

`handleRequested` and the locked replay guard check reserve activity only for
`charge`, not `sponsor`. The repeated same-calldata sponsor decision can return
positive with no known receipt and no remaining pool hold. This witness requires
neither replay of an expired signature nor late inclusion of the old operation.
Receipt reconciliation after a gas spike is a separate state, not this finding.

### GAS-POOL-CE-002: zero receipt before judgment leaves an orphan hold

```text
open A -> finalized A (known cost 0) -> judge A (hold 2)
```

The inline requested-versus-finalized race handling in `decideAndCommit` requires
`actualJpy > 0`. The known-zero path therefore leaves the hold unsettled.
Backfill and sweep select unknown actual costs, so neither releases this hold.
This finding is conditional on the admitted early/retained-receipt ordering;
reachability of that ordering through Pimlico is not independently established.
Known-zero receipts **after** the hold settle correctly in the model and tests.

### GAS-CHARGE-CE-001: retry inserts during an empty retroactive read

```text
prepare A -> nonce preflight -> submit A (reserve 2)
          -> expire A -> sweep A (refund 2)
          -> retry nonce preflight -> receipt A (cost 1)
          -> beginRetro A (no active spend found)
          -> retry submit A (new pending reserve 2)
          -> finishRetro A (confirmed debit 1)
```

The empty active-row read in `retroactiveDebitCancelledReserve` does not prevent
`commitChargeReserve` from inserting a pending row. The retroactive path later
locks the balance but does not recheck active spends. The schema has a partial
unique `(tx_hash, kind)` index, not a unique judgment constraint, so pending and
confirmed spends can coexist. The nonce preflight is before receipt arrival;
the witness does not assume a fresh stale-nonce submit would be accepted.
The model preserves this race instead of assuming all DB transactions serialize.

## Evidence

The 2026-11-13 run checked 13 safety invariants and 31 scenario tests:

| Check | Result | Reachable states |
|---|---|---:|
| Pool safety | PASS | 6,400 |
| Charge safety | PASS | 25,474 |
| Quota safety | PASS | 438,344 |
| Scenario tests | PASS | 31 tests |
| Three stronger properties | FAIL | One counterexample per property |

`./scripts/verify quick` and the complete `./scripts/verify model` regression
also passed. Evidence directories for this run are
`results/20261113T030026Z-bf192ee/`, `results/20261113T030043Z-bf192ee/`, and
`results/20261113T030157Z-bf192ee/`. Results are generated artifacts (git-ignored)
and CI uploads them. Each manifest records the API revision and SHA-256 of the
gas model inputs, including uncommitted model content. Re-run the commands above
to produce local manifests and full TLC logs; no API checkout or credentials are
needed to execute the models.
