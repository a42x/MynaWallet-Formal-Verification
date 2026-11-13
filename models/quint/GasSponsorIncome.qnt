module GasSponsorIncome {
  // API snapshot and abstraction boundaries: docs/gas-sponsor-model.md.
  val txs = Set("T1", "T2")
  val events = Set("P1", "C1")
  val ReservedAmount = 1
  val Estimate = 2
  type Entry = { state: str, amount: int }
  var state: {
    balance: int, depositSum: int, writeOffs: int, paidSum: int,
    refundsOut: int, creditsIn: int, absorbedOverrun: int,
    reserved: str, dep: str -> Entry, credits: str -> int,
    refunded: str -> int, events: str -> bool,
    spendPhase: str, actual: int,
  }
  val balance = state.balance
  val dep = state.dep

  action init = state' = {
    balance: 0, depositSum: 0, writeOffs: 0, paidSum: 0,
    refundsOut: 0, creditsIn: 0, absorbedOverrun: 0,
    reserved: "none",
    dep: txs.mapBy(_ => { state: "none", amount: 0 }),
    credits: txs.mapBy(_ => 0), refunded: txs.mapBy(_ => 0),
    events: events.mapBy(_ => false),
    spendPhase: "none", actual: -1,
  }

  pure def writeOffOf(bal: int): int = if (0 - bal > 0) 0 - bal else 0
  pure def flooredPlus(bal: int, a: int): int = (if (bal > 0) bal else 0) + a

  // reservePendingDeposit: a pending deposit row with no balance effect;
  // it only reserves balance-cap headroom.
  action reserveDep = all {
    state.reserved == "none",
    state' = state.with("reserved", "pending"),
  }

  action failDep = all {
    state.reserved == "pending",
    state' = state.with("reserved", "failed"),
  }

  // recordDeposit(tx, via, amount): worker deliveries carry the reservation's
  // userOpHash; webhook deliveries carry none. A confirmed tx short-circuits
  // every path (the partial (tx_hash, kind) unique index). Worker settle has
  // no amount filter; the webhook candidate settle requires an amount match.
  // Everything else inserts a fresh confirmed row and credits only the winner.
  action deposit(tx: str, via: str, amount: int): bool = {
    val writeOff = writeOffOf(state.balance)
    val committed = dep.get(tx).state == "confirmed"
    val workerSettle = via == "worker" and state.reserved == "pending"
    val webhookSettle = via == "webhook" and state.reserved == "pending"
      and amount == ReservedAmount
    val settleCredit =
      state.with("balance", flooredPlus(state.balance, amount))
        .with("depositSum", state.depositSum + amount)
        .with("writeOffs", state.writeOffs + writeOff)
    val settled = if (committed) state
      else if (workerSettle or webhookSettle)
      settleCredit.with("reserved", "settled")
        .with("credits", state.credits.set(tx, state.credits.get(tx) + 1))
        .with("dep", dep.set(tx, { state: "confirmed", amount: amount }))
      else settleCredit
        .with("credits", state.credits.set(tx, state.credits.get(tx) + 1))
        .with("dep", dep.set(tx, { state: "confirmed", amount: amount }))
    state' = settled
  }

  // refundDepositByTxHash: net reversal of a confirmed on-chain deposit.
  // The (tx_hash, kind='refund') partial unique makes a repeat a no-op; the
  // balance update never floors, so negative balances are allowed to persist.
  action refundDep(tx: str): bool = {
    val applied = state.with("refunded", state.refunded.set(tx, 1))
      .with("refundsOut", state.refundsOut + dep.get(tx).amount)
      .with("balance", state.balance - dep.get(tx).amount)
    state' = if (dep.get(tx).state == "confirmed" and state.refunded.get(tx) == 0)
      applied else state
  }

  // RevenueCat events: the gas_charge_iap_transactions event_id unique gates
  // purchase credit (creditIapPool, floored) and CANCELLATION debit
  // (debitIapPool, net, negative balances intentionally allowed).
  action iap(e: str, amount: int): bool = {
    val purchase = state.with("balance", flooredPlus(state.balance, amount))
      .with("depositSum", state.depositSum + amount)
      .with("writeOffs", state.writeOffs + writeOffOf(state.balance))
      .with("events", state.events.set(e, true))
    val cancellation = state.with("events", state.events.set(e, true))
      .with("balance", state.balance - amount)
      .with("refundsOut", state.refundsOut + amount)
    state' = if (state.events.get(e)) state
      else if (e == "C1") cancellation else purchase
  }

  // recordRefund: sponsorship reversal, modeled as at most one caller call.
  action sponsorRefund = {
    val applied = state.with("creditsIn", state.creditsIn + 1)
      .with("balance", state.balance + 1)
    state' = if (state.creditsIn < 1) applied else state
  }

  action reserveSpend = {
    val applied = state.with("balance", state.balance - Estimate)
      .with("paidSum", state.paidSum + Estimate)
      .with("spendPhase", "pending")
    state' = if (state.spendPhase == "none" and state.balance >= Estimate)
      applied else state
  }

  action cancelSpend = all {
    state.spendPhase == "pending",
    state' = state.with("balance", state.balance + Estimate)
      .with("paidSum", state.paidSum - Estimate)
      .with("spendPhase", "cancelled"),
  }

  action receipt(cost: int): bool = all {
    state.spendPhase == "pending",
    state.actual == -1,
    state' = state.with("actual", cost),
  }

  // finalizeSpend: split delta = actual - estimate between the user's
  // non-negative headroom and the operator.
  action finalizeSpend = {
    val delta = state.actual - Estimate
    val headroom = if (state.balance > 0) state.balance else 0
    val userPaid = if (delta < headroom) delta else headroom
    all {
      state.spendPhase == "pending",
      state.actual > 0,
      state' = state.with("balance", state.balance - userPaid)
        .with("paidSum", state.paidSum + userPaid)
        .with("absorbedOverrun", state.absorbedOverrun + delta - userPaid)
        .with("spendPhase", "confirmed"),
    }
  }

  action step = {
    nondet tx = txs.oneOf()
    nondet via = Set("worker", "webhook").oneOf()
    nondet amount = Set(1, 3).oneOf()
    nondet e = events.oneOf()
    nondet cost = Set(1, 2, 4).oneOf()
    any {
      reserveDep, failDep, deposit(tx, via, amount), refundDep(tx),
      iap(e, 2), sponsorRefund,
      reserveSpend, cancelSpend, receipt(cost), finalizeSpend,
    }
  }

  // balance == lifetime-deposit-gross + operator-written-off-debt
  //            + sponsorship-refund-in - external-refunds/debit-iap
  //            - user-paid (pending estimates + settled deltas)
  val incomeConservation =
    state.balance == state.depositSum + state.writeOffs + state.creditsIn
      - state.refundsOut - state.paidSum
  val depositCreditAtMostOnce = txs.forall(t => state.credits.get(t) <= 1)
  val refundAtMostOnce = txs.forall(t => state.refunded.get(t) <= 1)
  val absorbedSplit = state.absorbedOverrun >= 0 and state.writeOffs >= 0
  val safety = incomeConservation and depositCreditAtMostOnce and refundAtMostOnce
    and absorbedSplit
}
