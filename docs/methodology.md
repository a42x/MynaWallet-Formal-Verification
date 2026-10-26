---
title: Verification methodology
last_updated: 2026-10-26
tags:
  - formal-verification
  - quint
  - kontrol
  - foundry
---

# Verification methodology

## Two-level verification

### Protocol level

Quint models each chain as an independent recovery state machine. It explicitly models:

- delivery to each chain,
- duplicate submission,
- per-chain request consumption,
- pause state,
- guardian/configuration drift,
- operator reconciliation,
- partial fan-out.

Safety properties are checked independently from liveness assumptions.

### Off-chain level (API / relayer / guardian)

The same Quint model (`CrossChainRecovery.qnt`) extends the on-chain core with
the off-chain state machine realized by `a42x/api` (recovery feature) and
`a42x/api-infrastructure` (recovery-relayer / guardian2 KMS). It models:

- signed dispatch by the fan-out service, bounded to `MaxDispatches=2` attempts
  per chain, with retry only after an observed lost attempt and never after
  delivery (`CCR-API-001`),
- the guardian-approval signing deadline; no dispatch past it, bookkeeping
  frozen at passage (`CCR-API-002`),
- the API request status machine `pending_passkey -> completed/failed/
  expired/cancelled` and terminal stability (`CCR-API-003`),
- the per-identity cooldown gating a second sequential request (`CCR-API-004`),
- completion-notification idempotency between the eager path and the worker
  racing on the atomic DB claim (`CCR-API-005`),
- partial fan-out safety: execution only on dispatched, delivered chains, and
  requested-key convergence (`CCR-REL-001`),
- Guardian-2 signature availability before any dispatch (`CCR-REL-002`).

Abstraction assumptions:

- Guardian 1 signs in-process with KMS (`RECOVERY_RELAYER_KMS_KEY_PATH`);
  Guardian 2 is fetched over HTTP from the `nft-cosigner-template` Cloud Run
  service. Both are boolean availability conditions.
- The on-chain deadline in the guardian-approval TYPEHASH is enforced by the
  contract; the model reflects it as the `not deadlinePassed` submit guard and
  cross-checks it at the implementation layer.
- Relayer submission and chain inclusion are abstracted as
  dispatch -> (deliver | lose) -> submit.
- Bounded claim: 2 chains, at most 2 sequential requests per identity,
  clock in 0..3, at most 2 dispatches per chain.

### Implementation level

Kontrol targets the pinned Solidity implementation.

- Kontrol proves reachability claims against KEVM or performs bounded model checking.

The implementation-level monotonicity of `consumedRecoveryRequests` (former `CCR-CERTORA-001`) is **not claimed** by this repository; the Certora and Halmos toolchains were removed on 2026-10-26. The canonical-guardian-digest property is proved by Kontrol (`CCR-KONTROL-001`).

## Initial safety properties

1. A recovery request executes at most once per chain.
2. A consumed request corresponds to exactly one completed execution.
3. Successful execution installs the requested key.
4. If both chains execute the same request, both install the same key.
5. Delivery alone does not mutate wallet keys.
6. A paused chain cannot execute recovery.
7. Stale guardian configuration blocks the request on that chain.
8. A replay after consumption leaves state unchanged.

## Cross-chain assumptions

The protocol intentionally omits chain ID and verifying-contract domain separation from guardian approval messages. Therefore:

- cross-chain reuse is intentional,
- same-chain reuse must be blocked by local state,
- guardian and threshold changes are not automatically replicated,
- liveness requires a relayer to submit on every intended chain,
- safety on a stale chain requires operational guardian-state reconciliation.

The relayer part of the last two bullets is now internalized as bounded claims
(`CCR-REL-001/002`, `CCR-API-002`) in the off-chain layer above. No contract-level
tool can prove the remaining operational assumptions by itself.
