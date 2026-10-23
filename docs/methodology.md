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

### Implementation level

Certora, Halmos, and Kontrol target the pinned Solidity implementation.

- Certora proves inductive contract invariants under declared external-call summaries.
- Halmos searches symbolic execution paths under explicit loop and dynamic-data bounds.
- Kontrol proves reachability claims against KEVM or performs bounded model checking.

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

No contract-level tool can prove these operational assumptions by itself.
