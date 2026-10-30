---
title: Verification methodology
last_updated: 2026-10-30
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

### Authentication lifecycle model

`models/quint/AuthLifecycle.qnt` models the passkey authentication lifecycle
from `a42x/api` commit `8277832d744c8ce8e2b191fb06f13bff970babfb`.
The source revision and inspected paths are pinned in
`verification/auth-source.lock.json`.

The model is split into three independently checked modules:

- registration: signed eKYC token consumption, rollback ownership, WebAuthn
  challenge reads, transaction commit and one-passkey-per-identity constraints,
- login: atomic challenge consumption, discoverable-passkey login, unified
  anonymous failure classes and per-IP/per-endpoint throttling,
- session: refresh rotation, owner-preserving replacement, logout ownership,
  recovery/deletion revocation and stateless access-token expiry.

Cryptographic operations are symbolic. A guarded action represents successful
JWT/WebAuthn signature, RP-ID, origin and user-verification checks. Unpredictable
JWT IDs and challenge IDs are assumed unguessable. The model checks concurrency
and authorization state, not cryptographic hardness or side-channel timing.

Bounded claim:

- 2 identities and 2 concurrent registration requests,
- at most 2 generated login challenges and 3 observed requests per endpoint,
- 3 refresh tokens, 3 access tokens, access-token TTL of 2 model ticks,
- clock bounded to 4 ticks.

The passing safety conjunctions are `AUTH-REG-001..002`,
`AUTH-LOGIN-001..004` and `AUTH-SESSION-001..005`. Two stronger desired
properties have reproducible counterexamples:

- `AUTH-REG-CE-001`: registration uses `getRaw()` followed by `delete()`, so
  two requests that read the same challenge before either deletion can both
  commit. Each request still needs its own valid eKYC token and WebAuthn
  response; this is a challenge single-use failure, not a direct authentication
  bypass in the modeled threat boundary.
- `AUTH-SESSION-CE-001`: logout and recovery revoke refresh tokens but do not
  revoke already-issued stateless access JWTs. They remain usable until the
  configured short expiry.

The login enumeration claim compares externally exposed error classes only.
It does not prove response-time indistinguishability. The throttle claim is for
one modeled IP and the implementation's separate options/verify buckets; IP
rotation and distributed attackers remain operational concerns.

The API is passkey/eKYC based, so password confirmation and password-reset
flows are not present in this source snapshot. Recovery is represented by
refresh-token revocation and is complemented by the existing cross-chain
recovery model.

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
