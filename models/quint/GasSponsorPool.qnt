// API snapshot and abstraction boundaries: docs/gas-sponsor-model.md.
module GasSponsorPool {
  val ops = Set("A", "B")
  val InitialBalance = 3
  val Hold = 2
  type Entry = {
    outcome: str, finalized: bool, actual: int, reserve: int, debit: int,
    settled: bool, settlements: int, requests: int, elapsed: bool,
    reconcile: bool, responseBacked: bool,
  }
  var state: { balance: int, active: bool, entries: str -> Entry }
  val entries = state.entries
  val balance = state.balance

  action init = state' = {
    balance: InitialBalance, active: true,
    entries: ops.mapBy(_ => {
      outcome: "none", finalized: false, actual: -1, reserve: 0, debit: 0,
      settled: false, settlements: 0, requests: 0, elapsed: false,
      reconcile: false, responseBacked: true,
    }),
  }

  // claimPoolSettlement and settleReservation commit in the SAME transaction.
  pure def settle(b: int, e: Entry, cost: int): { balance: int, entry: Entry } = {
    val covered = b + e.reserve >= cost
    {
      balance: if (covered) b + e.reserve - cost else b,
      entry: e.with("settled", true).with("settlements", e.settlements + 1)
        .with("debit", if (covered) cost else e.debit)
        .with("reconcile", not(covered)),
    }
  }

  action open(op: str): bool = all {
    entries.get(op).outcome == "none",
    state' = state.with("entries", entries.set(op, entries.get(op).with("outcome", "evaluating"))),
  }

  // A correlation key and callData are fixed per op. Negative decisions can retry.
  action judge(op: str, commits: bool): bool = {
    val e = entries.get(op)
    val room = state.active and balance >= Hold
    val reserved = e.with("outcome", "sponsor").with("reserve", Hold)
      .with("debit", Hold).with("requests", e.requests + 1)
    val accounted = if (e.actual > 0) settle(balance - Hold, reserved, e.actual)
      else { balance: balance - Hold, entry: reserved }
    val backed = not(e.settled) or e.actual >= 0
    val replayed = e.with("requests", e.requests + 1)
      .with("responseBacked", e.responseBacked and backed)
    all {
      e.outcome != "none",
      e.requests < 2,
      state' = if (not(commits)) state
        else if (e.outcome == "sponsor") state.with("entries", entries.set(op, replayed))
        else if (room) state.with("balance", accounted.balance)
          .with("entries", entries.set(op, accounted.entry))
        else state.with("entries", entries.set(op,
          e.with("outcome", "denied").with("requests", e.requests + 1))),
    }
  }

  // Pimlico finalized means paymaster data filled, NOT on-chain confirmation.
  // -1 is an unavailable receipt; zero is a known receipt cost.
  action finalized(op: str, cost: int): bool = {
    val e = entries.get(op)
    val stamped = e.with("finalized", true).with("actual", cost)
    val result = if (e.outcome == "sponsor" and cost >= 0 and not(e.settled))
      settle(balance, stamped, cost) else { balance: balance, entry: stamped }
    all {
      e.outcome != "none",
      state' = if (e.finalized) state else state.with("balance", result.balance)
        .with("entries", entries.set(op, result.entry)),
    }
  }

  action backfill(op: str, cost: int): bool = {
    val e = entries.get(op)
    val stamped = e.with("actual", cost)
    val result = if (not(e.settled)) settle(balance, stamped, cost)
      else { balance: balance, entry: stamped }
    state' = if (e.finalized and e.outcome == "sponsor" and e.actual == -1)
      state.with("balance", result.balance).with("entries", entries.set(op, result.entry))
      else state
  }

  // elapsed abstracts the sponsor TTL and scan eligibility, not paymaster expiry.
  action expire(op: str): bool = all {
    entries.get(op).outcome == "sponsor",
    state' = state.with("entries", entries.set(op, entries.get(op).with("elapsed", true))),
  }

  action sweep(op: str, probe: str): bool = {
    val e = entries.get(op)
    val eligible = e.outcome == "sponsor" and e.finalized and e.elapsed
      and e.actual == -1 and not(e.settled) and probe == "unknown"
    val released = settle(balance, e, 0)
    state' = if (eligible) state.with("balance", released.balance)
      .with("entries", entries.set(op, released.entry)) else state
  }

  action setActive(active: bool): bool = state' = state.with("active", active)

  action step = {
    nondet op = ops.oneOf()
    any {
      open(op),
      { nondet commits = Set(false, true).oneOf()
        judge(op, commits) },
      { nondet cost = Set(-1, 0, 1, 2, 4).oneOf()
        finalized(op, cost) },
      { nondet cost = Set(0, 1, 2, 4).oneOf()
        backfill(op, cost) },
      expire(op),
      { nondet probe = Set("unknown", "known", "unavailable").oneOf()
        sweep(op, probe) },
      { nondet active = Set(false, true).oneOf()
        setActive(active) },
    }
  }

  val poolNonnegative = balance >= 0
  val poolConservation = balance + entries.get("A").debit + entries.get("B").debit
    == InitialBalance
  val settlementAtMostOnce = ops.forall(op => entries.get(op).settlements <= 1)
  val receiptAccounting = ops.forall(op => {
    val e = entries.get(op)
    e.debit >= 0 and
      (not(e.settled) implies (e.debit == e.reserve)) and
      ((e.settled and e.actual >= 0 and not(e.reconcile) and e.debit > 0)
        implies e.debit == e.actual)
  })
  val safety = poolNonnegative and poolConservation and settlementAtMostOnce and receiptAccounting

  // Stronger desired properties: intentionally excluded from the PASS conjunction.
  val replayBackedByFunds = ops.forall(op => entries.get(op).responseBacked)
  val knownReceiptSettled = ops.forall(op => {
    val e = entries.get(op)
    (e.outcome == "sponsor" and e.actual >= 0) implies e.settled
  })
}
