/*
 * Abstract protocol model for MynaWallet chain-id-less recovery fan-out.
 *
 * This model intentionally abstracts cryptography to a boolean configuration-validity
 * condition. Solidity-level tools verify the digest and signature-processing code.
 *
 * This revision adds the off-chain recovery state machine (a42x/api recovery
 * feature + api-infrastructure recovery-relayer) on top of the on-chain core:
 *
 * - fan-out dispatch is an explicit API-level action bounded by a signing
 *   deadline, an outstanding-attempt rule and a guardian-quorum condition,
 * - delivery loss and retries model the recovery-userop-retry worker,
 * - the API request status machine (pending_passkey -> completed/failed/
 *   expired/cancelled) and its terminal stability and cooldown rules,
 * - the completion-notification idempotency claim (atomic claim between the
 *   eager path and the sweep/retry worker).
 *
 * Abstraction assumptions (see docs/methodology.md):
 * - Guardian 1 signs in-process with KMS; Guardian 2 is fetched over HTTP from
 *   the nft-cosigner-template Cloud Run service. Both are abstracted to
 *   boolean availability conditions.
 * - The on-chain deadline check is part of the guardian-approval TYPEHASH and
 *   is enforced by the contract; here it is the `not deadlinePassed` guard on
 *   submit, cross-checked at the implementation layer (Kontrol / Foundry).
 * - Relayer submission and chain inclusion are abstracted into dispatch ->
 *   (deliver | lose) -> submit.
 */
module CrossChainRecovery {
  val InitialKey: int = 1
  val RequestedKey: int = 2

  // Bounded claim: 2 chains, at most 2 sequential requests per identity,
  // clock in 0..MaxTicks, at most MaxDispatches signed dispatch attempts per
  // chain. The signing deadline passes at DeadlineTick; the cooldown window
  // elapses at CooldownTick (DeadlineTick < CooldownTick).
  val chains = Set("A", "B")
  val MaxRequests: int = 2
  val MaxTicks: int = 3
  val MaxDispatches: int = 2
  val DeadlineTick: int = 2
  val CooldownTick: int = 3

  // ----- on-chain state (per chain) -----
  var delivery: str -> bool // UserOp observed included by the chain
  var consumed: str -> bool // on-chain replay guard consumed
  var executions: str -> int
  var key: str -> int
  var paused: str -> bool
  var configFresh: str -> bool

  // ----- off-chain fan-out state (per chain) -----
  var dispatches: str -> int // signed+dispatched UserOp attempts
  var losses: str -> int // dispatch attempts observed lost before delivery

  // ----- API request state machine -----
  var status: str // "none"|"pending"|"completed"|"failed"|"expired"|"cancelled"
  var terminalStatus: str // "none" until the request terminalizes, then frozen
  var clock: int
  var deadlinePassed: bool
  var dispatchSnapshot: str -> int // dispatch counts at deadline passage
  var cooldownElapsed: bool // sticky: a cooldown window has elapsed
  var requestsTotal: int
  var notifyCount: int
  var sig2: bool // guardian-2 HTTP signature available

  action init = all {
    delivery' = chains.mapBy(ch => false),
    consumed' = chains.mapBy(ch => false),
    executions' = chains.mapBy(ch => 0),
    key' = chains.mapBy(ch => InitialKey),
    paused' = chains.mapBy(ch => false),
    configFresh' = chains.mapBy(ch => true),
    dispatches' = chains.mapBy(ch => 0),
    losses' = chains.mapBy(ch => 0),
    status' = "none",
    terminalStatus' = "none",
    clock' = 0,
    deadlinePassed' = false,
    dispatchSnapshot' = chains.mapBy(ch => 0),
    cooldownElapsed' = false,
    requestsTotal' = 0,
    notifyCount' = 0,
    sig2' = false,
  }

  // Frame helpers: every `step` branch must update the same variables, so
  // actions fill unrelated groups with these keep-frames.
  action keepChain = all {
    delivery' = delivery,
    consumed' = consumed,
    executions' = executions,
    key' = key,
    paused' = paused,
    configFresh' = configFresh,
    dispatches' = dispatches,
    losses' = losses,
  }

  action keepChainNotDispatches = all {
    delivery' = delivery,
    consumed' = consumed,
    executions' = executions,
    key' = key,
    paused' = paused,
    configFresh' = configFresh,
    losses' = losses,
  }

  action keepChainNotLosses = all {
    delivery' = delivery,
    consumed' = consumed,
    executions' = executions,
    key' = key,
    paused' = paused,
    configFresh' = configFresh,
    dispatches' = dispatches,
  }

  action keepChainNotDelivery = all {
    consumed' = consumed,
    executions' = executions,
    key' = key,
    paused' = paused,
    configFresh' = configFresh,
    dispatches' = dispatches,
    losses' = losses,
  }

  action keepChainNotPaused = all {
    delivery' = delivery,
    consumed' = consumed,
    executions' = executions,
    key' = key,
    configFresh' = configFresh,
    dispatches' = dispatches,
    losses' = losses,
  }

  action keepChainNotConfig = all {
    delivery' = delivery,
    consumed' = consumed,
    executions' = executions,
    key' = key,
    paused' = paused,
    dispatches' = dispatches,
    losses' = losses,
  }

  action keepChainNotExec = all {
    delivery' = delivery,
    paused' = paused,
    configFresh' = configFresh,
    dispatches' = dispatches,
    losses' = losses,
  }

  action keepApi = all {
    status' = status,
    terminalStatus' = terminalStatus,
    clock' = clock,
    deadlinePassed' = deadlinePassed,
    dispatchSnapshot' = dispatchSnapshot,
    cooldownElapsed' = cooldownElapsed,
    requestsTotal' = requestsTotal,
    notifyCount' = notifyCount,
    sig2' = sig2,
  }

  /* API keep-frames scoped by which members an action updates. */
  action keepApiNotClockCooldown = all {
    status' = status,
    terminalStatus' = terminalStatus,
    deadlinePassed' = deadlinePassed,
    dispatchSnapshot' = dispatchSnapshot,
    requestsTotal' = requestsTotal,
    notifyCount' = notifyCount,
    sig2' = sig2,
  }

  action keepApiNotDeadline = all {
    clock' = clock,
    cooldownElapsed' = cooldownElapsed,
    requestsTotal' = requestsTotal,
    notifyCount' = notifyCount,
    sig2' = sig2,
  }

  action keepApiNotStatus = all {
    clock' = clock,
    deadlinePassed' = deadlinePassed,
    dispatchSnapshot' = dispatchSnapshot,
    cooldownElapsed' = cooldownElapsed,
    requestsTotal' = requestsTotal,
    notifyCount' = notifyCount,
    sig2' = sig2,
  }

  action keepApiNotSig2 = all {
    status' = status,
    terminalStatus' = terminalStatus,
    clock' = clock,
    deadlinePassed' = deadlinePassed,
    dispatchSnapshot' = dispatchSnapshot,
    cooldownElapsed' = cooldownElapsed,
    requestsTotal' = requestsTotal,
    notifyCount' = notifyCount,
  }

  action keepApiNotNotify = all {
    status' = status,
    terminalStatus' = terminalStatus,
    clock' = clock,
    deadlinePassed' = deadlinePassed,
    dispatchSnapshot' = dispatchSnapshot,
    cooldownElapsed' = cooldownElapsed,
    requestsTotal' = requestsTotal,
    sig2' = sig2,
  }

  /* JPKI verify succeeds and a recovery request is created. A second request
   * for the same identity requires the previous one to be terminal and its
   * cooldown window to have elapsed (recovery-cooldown-check.service). */
  action verifyAndCreate = all {
    (
      (status == "none" and requestsTotal == 0) or
        (not(status == "none") and not(status == "pending") and
          cooldownElapsed and requestsTotal < MaxRequests)
    ),
    status' = "pending",
    delivery' = chains.mapBy(ch => false),
    consumed' = chains.mapBy(ch => false),
    executions' = chains.mapBy(ch => 0),
    key' = chains.mapBy(ch => InitialKey),
    dispatches' = chains.mapBy(ch => 0),
    losses' = chains.mapBy(ch => 0),
    terminalStatus' = "none",
    clock' = 0,
    deadlinePassed' = false,
    dispatchSnapshot' = chains.mapBy(ch => 0),
    cooldownElapsed' = cooldownElapsed,
    requestsTotal' = requestsTotal + 1,
    notifyCount' = 0,
    sig2' = false,
    paused' = paused,
    configFresh' = configFresh,
  }

  action tick = all {
    clock < MaxTicks,
    clock' = clock + 1,
    // The cooldown observation is sticky across requests.
    cooldownElapsed' = (cooldownElapsed or clock + 1 >= CooldownTick),
    keepApiNotClockCooldown,
    keepChain,
  }

  /* The guardian-approval deadline passes. The API freezes its fan-out
   * bookkeeping at this instant; a pending request becomes expired. */
  action deadlinePass = all {
    clock >= DeadlineTick,
    not(deadlinePassed),
    deadlinePassed' = true,
    dispatchSnapshot' = dispatches,
    if (status == "pending") {
      all { status' = "expired", terminalStatus' = "expired" }
    } else {
      all { status' = status, terminalStatus' = terminalStatus }
    },
    keepApiNotDeadline,
    keepChain,
  }

  action complete = all {
    status == "pending",
    chains.exists(ch => executions.get(ch) == 1),
    status' = "completed",
    terminalStatus' = "completed",
    keepApiNotStatus,
    keepChain,
  }

  action failRequest = all {
    status == "pending",
    status' = "failed",
    terminalStatus' = "failed",
    keepApiNotStatus,
    keepChain,
  }

  action cancel = all {
    status == "pending",
    status' = "cancelled",
    terminalStatus' = "cancelled",
    keepApiNotStatus,
    keepChain,
  }

  /* Guardian-2 HTTP fetch against the nft-cosigner-template service succeeds.
   * Fetch failures are the absence of this action: no signature yet. */
  action fetchG2 = all {
    not(sig2),
    sig2' = true,
    keepApiNotSig2,
    keepChain,
  }

  /* The recovery-fanout service signs (Guardian 1 KMS + Guardian 2 fetched)
   * and dispatches a UserOp for one chain. Requires: an active request, a
   * live signing deadline, no outstanding attempt on the chain, no already
   * delivered payload, and the fetched Guardian 2 signature (quorum). */
  action dispatch(ch) = all {
    status == "pending",
    not(deadlinePassed),
    not(delivery.get(ch)),
    dispatches.get(ch) == losses.get(ch), // nothing outstanding
    dispatches.get(ch) < MaxDispatches, // bounded claim: retries are capped
    sig2,
    dispatches' = dispatches.setBy(ch, d => d + 1),
    keepChainNotDispatches,
    keepApi,
  }

  /* A dispatched UserOp is observed lost (submission failure / retryable). */
  action lose(ch) = all {
    dispatches.get(ch) > losses.get(ch),
    not(delivery.get(ch)),
    losses' = losses.setBy(ch, l => l + 1),
    keepChainNotLosses,
    keepApi,
  }

  /* A dispatched UserOp is included on the chain. Requires an outstanding
   * dispatch: delivery is impossible without a prior signed dispatch. */
  action deliver(ch) = all {
    dispatches.get(ch) > losses.get(ch),
    not(delivery.get(ch)),
    delivery' = delivery.set(ch, true),
    keepChainNotDelivery,
    keepApi,
  }

  /* On-chain execution. `not deadlinePassed` models the guardian-approval
   * TYPEHASH deadline enforced by the contract (asserted at the
   * implementation layer via Kontrol / Foundry). */
  action submit(ch) = all {
    delivery.get(ch),
    not(consumed.get(ch)),
    not(paused.get(ch)),
    configFresh.get(ch),
    not(deadlinePassed),
    consumed' = consumed.set(ch, true),
    executions' = executions.setBy(ch, e => e + 1),
    key' = key.set(ch, RequestedKey),
    keepChainNotExec,
    keepApi,
  }

  action replayRejected(ch) = all {
    consumed.get(ch),
    keepChain,
    keepApi,
  }

  action pause(ch) = all {
    not(paused.get(ch)),
    paused' = paused.set(ch, true),
    keepChainNotPaused,
    keepApi,
  }

  action unpause(ch) = all {
    paused.get(ch),
    paused' = paused.set(ch, false),
    keepChainNotPaused,
    keepApi,
  }

  action rotate(ch) = all {
    configFresh.get(ch),
    configFresh' = configFresh.set(ch, false),
    keepChainNotConfig,
    keepApi,
  }

  action reconcile(ch) = all {
    not(configFresh.get(ch)),
    configFresh' = configFresh.set(ch, true),
    keepChainNotConfig,
    keepApi,
  }

  /* Completion-notification idempotency: two racing paths (the eager check in
   * the completion service and the last-chain flip in the worker) both attempt
   * the push. The DB-level atomic claim must admit at most one. */
  action notifyEager = all {
    status == "completed",
    notifyCount == 0,
    notifyCount' = 1,
    keepChain,
    keepApiNotNotify,
  }

  action notifyWorker = all {
    status == "completed",
    notifyCount == 0,
    notifyCount' = 1,
    keepChain,
    keepApiNotNotify,
  }

  action step = any {
    verifyAndCreate,
    tick,
    deadlinePass,
    complete,
    failRequest,
    cancel,
    fetchG2,
    notifyEager,
    notifyWorker,
    dispatch("A"),
    dispatch("B"),
    lose("A"),
    lose("B"),
    deliver("A"),
    deliver("B"),
    submit("A"),
    submit("B"),
    replayRejected("A"),
    replayRejected("B"),
    pause("A"),
    pause("B"),
    unpause("A"),
    unpause("B"),
    rotate("A"),
    rotate("B"),
    reconcile("A"),
    reconcile("B"),
  }

  // ----- invariants -----

  // on-chain core (CCR-MODEL-001..004)
  val atMostOncePerChain = chains.forall(ch => executions.get(ch) <= 1)

  val consumedExactlyWhenExecuted = chains.forall(
    ch => consumed.get(ch) == (executions.get(ch) == 1)
  )

  val executionInstallsRequestedKey = chains.forall(
    ch => (executions.get(ch) == 1) implies (key.get(ch) == RequestedKey)
  )

  val noMutationBeforeExecution = chains.forall(
    ch => (executions.get(ch) == 0) implies (key.get(ch) == InitialKey)
  )

  val samePayloadConverges = chains.forall(
    ch => (executions.get(ch) == 1) implies (key.get(ch) == RequestedKey)
  )

  // CCR-REL-001: partial fan-out safety: only dispatched chains execute, and
  // every executed chain installs the same requested key.
  val rel001_partialFanoutSafety = chains.forall(ch =>
    (executions.get(ch) == 1) implies
      all {
        dispatches.get(ch) > 0,
        delivery.get(ch),
        key.get(ch) == RequestedKey,
      }
  )

  // CCR-REL-002: a dispatch requires the Guardian-2 signature to be available.
  val rel002_quorumRequired = chains.forall(
    ch => (dispatches.get(ch) > 0) implies sig2
  )

  // CCR-API-001: at most one outstanding dispatch per chain; retry only after
  // the previous attempt was observed lost; no retry after delivery.
  val api001_noDuplicateDispatch = chains.forall(ch =>
    all {
      dispatches.get(ch) <= losses.get(ch) + 1,
      delivery.get(ch) implies (dispatches.get(ch) == losses.get(ch) + 1),
    }
  )

  // CCR-API-002: no signing/dispatch after the guardian-approval deadline.
  val api002_noSignAfterDeadline = chains.forall(
    ch =>
      deadlinePassed implies
        (dispatches.get(ch) == dispatchSnapshot.get(ch))
  )

  // CCR-API-003: a terminal request status never leaves the terminal state.
  val api003_terminalStable =
    (terminalStatus != "none") implies (status == terminalStatus)

  // CCR-API-004: a second request exists only after a cooldown window
  // elapsed, and the number of requests is bounded.
  val api004_cooldownBeforeSecondRequest =
    (requestsTotal <= MaxRequests) and
      ((requestsTotal >= 2) implies cooldownElapsed)

  // CCR-API-005: at most one completion notification, whichever racing path
  // wins the atomic claim.
  val api005_atMostOnceNotification = notifyCount <= 1

  val safety =
    atMostOncePerChain and
      consumedExactlyWhenExecuted and
      executionInstallsRequestedKey and
      noMutationBeforeExecution and
      samePayloadConverges and
      rel001_partialFanoutSafety and
      rel002_quorumRequired and
      api001_noDuplicateDispatch and
      api002_noSignAfterDeadline and
      api003_terminalStable and
      api004_cooldownBeforeSecondRequest and
      api005_atMostOnceNotification
}

module CrossChainRecoveryTests {
  import CrossChainRecovery.*

  run fanoutSuccessTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(dispatch("B"))
      .then(deliver("A"))
      .then(deliver("B"))
      .then(submit("A"))
      .then(submit("B"))
      .expect(executions.get("A") == 1)
      .expect(executions.get("B") == 1)
      .then(complete)
      .expect(status == "completed")

  run replayIsRejectedTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(deliver("A"))
      .then(submit("A"))
      .then(replayRejected("A"))
      .expect(executions.get("A") == 1)

  run retryAfterLostDispatchTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(lose("A"))
      .then(dispatch("A"))
      .then(deliver("A"))
      .then(submit("A"))
      .expect(dispatches.get("A") == 2)
      .expect(losses.get("A") == 1)
      .expect(executions.get("A") == 1)

  run staleConfigCausesPartialRecoveryTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(rotate("B"))
      .then(dispatch("A"))
      .then(dispatch("B"))
      .then(deliver("A"))
      .then(deliver("B"))
      .then(submit("A"))
      .expect(executions.get("A") == 1)
      .expect(executions.get("B") == 0)
      .expect(configFresh.get("B") == false)

  run reconcileAllowsDelayedRecoveryTest =
    init
      .then(rotate("B"))
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("B"))
      .then(deliver("B"))
      .then(reconcile("B"))
      .then(submit("B"))
      .expect(executions.get("B") == 1)

  run pauseBlocksUntilUnpausedTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(deliver("A"))
      .then(pause("A"))
      .then(unpause("A"))
      .then(submit("A"))
      .expect(executions.get("A") == 1)

  run deadlineBlocksSigningTest =
    init
      .then(verifyAndCreate)
      .then(tick)
      .then(tick)
      .then(deadlinePass)
      .then(fetchG2)
      .expect(status == "expired")
      .expect(deadlinePassed)
      .expect(chains.forall(ch => dispatches.get(ch) == 0))

  run partialFanoutOnlyOneChainTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(deliver("A"))
      .then(submit("A"))
      .expect(executions.get("A") == 1)
      .expect(delivery.get("B") == false)
      .expect(dispatches.get("B") == 0)

  run cooldownGatesSecondRequestTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(deliver("A"))
      .then(submit("A"))
      .then(complete)
      .then(tick)
      .then(tick)
      .then(tick)
      .expect(cooldownElapsed)
      .then(verifyAndCreate)
      .expect(requestsTotal == 2)
      .expect(status == "pending")

  run completionNotificationAtMostOnceTest =
    init
      .then(verifyAndCreate)
      .then(fetchG2)
      .then(dispatch("A"))
      .then(deliver("A"))
      .then(submit("A"))
      .then(complete)
      .then(notifyEager)
      // The racing worker path is blocked by the atomic claim: notifyWorker is
      // not enabled here (guard notifyCount == 0 no longer holds), so the
      // notification count stays at exactly one.
      .expect(notifyCount == 1)
}