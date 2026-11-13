module GasSponsorCharge {
  // Two judgments on different chains share one user's chain_id=0 balance.
  val ops = Set("A", "B")
  val InitialBalance = 3
  val Estimate = 2
  type Entry = {
    prepared: bool, pending: bool, cancelled: bool, confirmed: bool,
    reserves: int, refunds: int, normalFinalizes: int, confirmations: int,
    actual: int, paid: int, absorbed: int, elapsed: bool, retroRead: bool, preflight: bool,
  }
  var state: { balance: int, frozen: bool, entries: str -> Entry }
  val entries = state.entries
  val balance = state.balance

  action init = state' = {
    balance: InitialBalance, frozen: false,
    entries: ops.mapBy(_ => {
      prepared: false, pending: false, cancelled: false, confirmed: false,
      reserves: 0, refunds: 0, normalFinalizes: 0, confirmations: 0,
      actual: -1, paid: 0, absorbed: 0, elapsed: false, retroRead: false, preflight: false,
    }),
  }

  action prepare(op: str): bool = all {
    balance >= Estimate,
    state' = state.with("entries", entries.set(op, entries.get(op).with("prepared", true))),
  }

  // A submit may pass the API nonce check before inclusion/receipt arrival,
  // then reach the DB reserve after a concurrent receipt worker has started.
  action preflight(op: str): bool = all {
    entries.get(op).prepared,
    entries.get(op).actual == -1,
    state' = state.with("entries", entries.set(op, entries.get(op).with("preflight", true))),
  }

  // commitChargeReserve holds the judgment lock; recordSpend locks the balance.
  action submit(op: str, commits: bool): bool = {
    val e = entries.get(op)
    val canDebit = e.prepared and not(e.pending) and not(e.confirmed)
      and not(state.frozen) and balance >= Estimate and e.reserves < 2
    val checked = e.with("preflight", false)
    val reserved = checked.with("pending", true).with("reserves", e.reserves + 1)
      .with("elapsed", false)
    all {
      e.preflight,
      state' = if (commits and canDebit) state.with("balance", balance - Estimate)
        .with("entries", entries.set(op, reserved))
        else state.with("entries", entries.set(op, checked)),
    }
  }

  action expire(op: str): bool = all {
    entries.get(op).pending,
    state' = state.with("entries", entries.set(op, entries.get(op).with("elapsed", true))),
  }

  action sweep(op: str, probe: str): bool = {
    val e = entries.get(op)
    val canRefund = e.pending and e.elapsed and e.actual == -1 and probe == "unknown"
    val refunded = e.with("pending", false).with("cancelled", true)
      .with("refunds", e.refunds + 1)
    state' = if (canRefund) state.with("balance", balance + Estimate)
      .with("entries", entries.set(op, refunded)) else state
  }

  // Judgment receipt storage and the charge-ledger transaction are separate.
  // A retry can run between them. A fixed receipt/tx hash is used per judgment.
  action receipt(op: str, cost: int): bool = all {
    entries.get(op).reserves > 0,
    entries.get(op).actual == -1,
    state' = state.with("entries", entries.set(op, entries.get(op).with("actual", cost))),
  }

  action finalizeSpend(op: str): bool = {
    val e = entries.get(op)
    val delta = e.actual - Estimate
    val userDelta = if (delta < balance) delta else balance
    val completed = e.with("pending", false).with("confirmed", true)
      .with("paid", Estimate + userDelta).with("absorbed", delta - userDelta)
      .with("normalFinalizes", e.normalFinalizes + 1)
      .with("confirmations", e.confirmations + 1)
    state' = if (e.pending and not(e.confirmed) and e.actual > 0)
      state.with("balance", balance - userDelta).with("entries", entries.set(op, completed))
      else state
  }

  // An empty SELECT ... FOR UPDATE does NOT lock a future spend row.
  // Keep this read separate: submit may insert a new pending row before the
  // retroactive transaction acquires the balance lock and inserts its row.
  action beginRetro(op: str): bool = all {
    entries.get(op).cancelled,
    not(entries.get(op).pending),
    not(entries.get(op).confirmed),
    not(entries.get(op).retroRead),
    entries.get(op).actual > 0,
    state' = state.with("entries", entries.set(op, entries.get(op).with("retroRead", true))),
  }

  action finishRetro(op: str, commits: bool): bool = {
    val e = entries.get(op)
    val paid = if (e.actual < balance) e.actual else balance
    val completed = e.with("confirmed", true).with("retroRead", false)
      .with("paid", paid).with("absorbed", e.actual - paid)
      .with("confirmations", e.confirmations + 1)
    all {
      e.retroRead,
      // The unique (tx_hash, kind) index rejects a second confirmed insert.
      // There is no unique judgment_id index, so pending is NOT a guard here.
      state' = if (commits and not(e.confirmed))
        state.with("balance", balance - paid).with("entries", entries.set(op, completed))
        else state.with("entries", entries.set(op, e.with("retroRead", false))),
    }
  }

  action setFrozen(frozen: bool): bool = state' = state.with("frozen", frozen)

  action step = {
    nondet op = ops.oneOf()
    any {
      prepare(op), preflight(op),
      { nondet commits = Set(false, true).oneOf()
        submit(op, commits) },
      expire(op),
      { nondet probe = Set("unknown", "known", "unavailable").oneOf()
        sweep(op, probe) },
      { nondet cost = Set(0, 1, 2, 4).oneOf()
        receipt(op, cost) },
      finalizeSpend(op), beginRetro(op),
      { nondet commits = Set(false, true).oneOf()
        finishRetro(op, commits) },
      { nondet frozen = Set(false, true).oneOf()
        setFrozen(frozen) },
    }
  }

  val chargeNonnegative = balance >= 0
  def accounted(op: str): int = {
    val e = entries.get(op)
    e.paid + (if (e.pending) Estimate else 0)
  }
  val chargeConservation = balance + accounted("A") + accounted("B") == InitialBalance
  val reserveAccounting = ops.forall(op => {
    val e = entries.get(op)
    e.reserves - e.refunds - e.normalFinalizes == (if (e.pending) 1 else 0)
      and e.refunds <= e.reserves
  })
  val confirmedCostSplit = ops.forall(op => {
    val e = entries.get(op)
    e.paid >= 0 and e.absorbed >= 0 and
      (e.confirmed implies e.paid + e.absorbed == e.actual)
  })
  val confirmationAtMostOnce = ops.forall(op => entries.get(op).confirmations <= 1)
  val safety = chargeNonnegative and chargeConservation and reserveAccounting
    and confirmedCostSplit and confirmationAtMostOnce

  val oneActiveSpendPerJudgment = ops.forall(op =>
    not(entries.get(op).pending and entries.get(op).confirmed))
}
