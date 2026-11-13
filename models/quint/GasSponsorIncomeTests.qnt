module GasSponsorIncomeTests {
  import GasSponsorIncome as Income from "./GasSponsorIncome"

  run shouldCreditWebhookDepositOnceTest =
    Income::init.then(Income::reserveDep)
      .then(Income::deposit("T1", "webhook", 3)).then(Income::deposit("T1", "webhook", 3))
      .expect(Income::state.balance == 3).expect(Income::incomeConservation)

  run shouldSettleReservationWithWorkerAmountTest =
    Income::init.then(Income::reserveDep)
      .then(Income::deposit("T1", "worker", 3))
      .expect(Income::state.balance == 3)
      .expect(Income::dep.get("T1").amount == 3).expect(Income::incomeConservation)

  run shouldIgnoreReservationOnAmountMismatchTest =
    Income::init.then(Income::reserveDep)
      .then(Income::deposit("T1", "webhook", 3))
      .expect(Income::state.reserved == "pending")
      .expect(Income::state.balance == 3)

  run shouldSettleReservationOnAmountMatchTest =
    Income::init.then(Income::reserveDep)
      .then(Income::deposit("T1", "webhook", 1))
      .expect(Income::state.reserved == "settled")
      .expect(Income::state.balance == 1)

  run shouldKeepOneCreditWhenWorkerAndWebhookRaceTest =
    Income::init.then(Income::reserveDep)
      .then(Income::deposit("T1", "webhook", 1)).then(Income::deposit("T1", "worker", 3))
      .expect(Income::state.balance == 1).expect(Income::incomeConservation)

  run shouldKeepOneCreditWhenDepositWasFailedTest =
    Income::init.then(Income::reserveDep).then(Income::failDep)
      .then(Income::deposit("T1", "webhook", 3))
      .expect(Income::state.balance == 3).expect(Income::incomeConservation)

  run shouldNetsRefundAgainstRealBalanceTest =
    Income::init.then(Income::deposit("T1", "webhook", 3))
      .then(Income::refundDep("T1"))
      .expect(Income::state.balance == 0).expect(Income::incomeConservation)

  run shouldRefundOnlyOncePerTxTest =
    Income::init.then(Income::deposit("T1", "webhook", 3))
      .then(Income::refundDep("T1")).then(Income::refundDep("T1"))
      .expect(Income::state.refundsOut == 3).expect(Income::incomeConservation)

  run shouldNotRefundUnconfirmedDepositTest =
    Income::init.then(Income::refundDep("T1"))
      .expect(Income::state.refundsOut == 0)

  run shouldFloorDebtWhenFreshMoneyArrivesTest =
    Income::init.then(Income::iap("C1", 2)).then(Income::deposit("T1", "webhook", 3))
      .expect(Income::state.balance == 3)
      .expect(Income::state.writeOffs == 2).expect(Income::incomeConservation)

  run shouldAllowNegativeBalanceOnCancellationTest =
    Income::init.then(Income::iap("C1", 2))
      .expect(Income::state.balance == -2).expect(Income::incomeConservation)

  run shouldIgnoreDuplicateEventDeliveryTest =
    Income::init.then(Income::iap("P1", 2)).then(Income::iap("P1", 2))
      .expect(Income::state.balance == 2).expect(Income::incomeConservation)

  run shouldSplitReceiptCostWithOperatorTest =
    Income::init.then(Income::deposit("T1", "webhook", 3))
      .then(Income::reserveSpend).then(Income::receipt(4))
      .then(Income::finalizeSpend)
      .expect(Income::state.balance == 0)
      .expect(Income::state.absorbedOverrun == 1).expect(Income::incomeConservation)

  run shouldRefundSponsorshipReversalOnceTest =
    Income::init.then(Income::sponsorRefund).then(Income::sponsorRefund)
      .expect(Income::state.creditsIn == 1).expect(Income::incomeConservation)

  run shouldRestoreDepositOnCancelSpendTest =
    Income::init.then(Income::deposit("T1", "webhook", 3))
      .then(Income::reserveSpend).then(Income::cancelSpend)
      .expect(Income::state.balance == 3).expect(Income::incomeConservation)
}
