module GasSponsorQuota {
  // One identity across two chains; quota keys do not include chainId.
  val ops = Set("A", "B")
  val scopes = Set("shared", "sponsorA", "sponsorB")
  val DailyLimit = 1
  type Entry = {
    outcome: str, intent: int, scope: str, slot: bool, claims: int,
    claimedScope: str, claimIntent: int, claimedPolicyActive: bool,
    lookedUp: bool, submittedIntent: int, response: str,
  }
  var state: {
    entries: str -> Entry, counts: str -> int, policies: str -> bool,
  }
  val entries = state.entries
  val counts = state.counts

  action init = state' = {
    counts: scopes.mapBy(_ => 0), policies: scopes.mapBy(_ => true),
    entries: ops.mapBy(_ => {
      outcome: "none", intent: 0, scope: "shared", slot: false, claims: 0,
      claimedScope: "shared", claimIntent: 0, claimedPolicyActive: false,
      lookedUp: false, submittedIntent: 0, response: "none",
    }),
  }

  action prepare(op: str, scope: str, outcome: str, intent: int): bool = all {
    entries.get(op).outcome == "none",
    state' = state.with("entries", entries.set(op, entries.get(op)
      .with("scope", scope).with("outcome", outcome).with("intent", intent))),
  }

  // Re-prepare may change the outcome/intent while submit's lookup is in flight.
  // Policy scope is fixed in this slice; reconfiguration after a claim is excluded.
  action reprepare(op: str, outcome: str, intent: int): bool = all {
    entries.get(op).outcome != "none",
    not(entries.get(op).slot),
    state' = state.with("entries", entries.set(op,
      entries.get(op).with("outcome", outcome).with("intent", intent))),
  }

  action lookup(op: str, intent: int): bool = all {
    entries.get(op).outcome != "none",
    state' = state.with("entries", entries.set(op, entries.get(op)
      .with("lookedUp", true).with("submittedIntent", intent))),
  }

  // commitSponsorSlot rereads the locked row, then atomically claims the counter
  // and stamps slot_finalized_at. Bundler failure AFTER commit does not refund it.
  action commit(op: str, commits: bool): bool = {
    val e = entries.get(op)
    val sameIntent = e.intent == e.submittedIntent
    val allowed = state.policies.get(e.scope) and counts.get(e.scope) < DailyLimit
    val response = if (e.outcome != "sponsor") "noop"
      else if (not(sameIntent)) "insufficient"
      else if (e.slot or allowed) "committed" else "insufficient"
    val claim = response == "committed" and not(e.slot)
    val updated = e.with("lookedUp", false).with("response", response)
    val claimed = updated.with("slot", true).with("claims", e.claims + 1)
      .with("claimedScope", e.scope).with("claimIntent", e.submittedIntent)
      .with("claimedPolicyActive", state.policies.get(e.scope))
    all {
      e.lookedUp,
      state' = if (not(commits)) state else
        state.with("entries", entries.set(op, if (claim) claimed else updated))
          .with("counts", if (claim) counts.set(e.scope, counts.get(e.scope) + 1) else counts),
    }
  }

  action setPolicy(scope: str, active: bool): bool =
    state' = state.with("policies", state.policies.set(scope, active))

  action step = {
    nondet op = ops.oneOf()
    any {
      { nondet scope = scopes.oneOf()
        nondet outcome = Set("sponsor", "charge", "denied").oneOf()
        nondet intent = Set(1, 2).oneOf()
        prepare(op, scope, outcome, intent) },
      { nondet outcome = Set("sponsor", "charge", "denied").oneOf()
        nondet intent = Set(1, 2).oneOf()
        reprepare(op, outcome, intent) },
      { nondet intent = Set(1, 2).oneOf()
        lookup(op, intent) },
      { nondet commits = Set(false, true).oneOf()
        commit(op, commits) },
      { nondet scope = scopes.oneOf()
        nondet active = Set(false, true).oneOf()
        setPolicy(scope, active) },
    }
  }

  val quotaBound = scopes.forall(scope => counts.get(scope) >= 0 and counts.get(scope) <= DailyLimit)
  val slotAtMostOnce = ops.forall(op => entries.get(op).claims <= 1)
  val scopedAccounting = scopes.forall(scope =>
    counts.get(scope) == ops.filter(op => {
      val e = entries.get(op)
      e.slot and e.claimedScope == scope
    }).size())
  val authorizedClaim = ops.forall(op => {
    val e = entries.get(op)
    e.slot implies (e.outcome == "sponsor" and e.claimedPolicyActive
      and e.intent == e.claimIntent and e.claims == 1)
  })
  val safety = quotaBound and slotAtMostOnce and scopedAccounting and authorizedClaim
}
