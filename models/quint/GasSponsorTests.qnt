module GasSponsorTests {
  import GasSponsorPool as Pool from "./GasSponsorPool"
  import GasSponsorCharge as Charge from "./GasSponsorCharge"
  import GasSponsorQuota as Quota from "./GasSponsorQuota"

  run shouldReserveOnceWhenRequestedIsRetriedTest =
    Pool::init.then(Pool::open("A"))
      .then(Pool::judge("A", true)).then(Pool::judge("A", true))
      .expect(Pool::balance == 1).expect(Pool::safety)

  run shouldRejectSecondHoldWhenPoolIsExhaustedTest =
    Pool::init.then(Pool::open("A")).then(Pool::open("B"))
      .then(Pool::judge("A", true)).then(Pool::judge("B", true))
      .expect(Pool::entries.get("B").outcome == "denied")
      .expect(Pool::balance == 1).expect(Pool::safety)

  run shouldNotReserveWhenPoolIsPausedTest =
    Pool::init.then(Pool::open("A")).then(Pool::setActive(false))
      .then(Pool::judge("A", true))
      .expect(Pool::balance == 3)
      .expect(Pool::entries.get("A").outcome == "denied")

  run shouldRollBackWhenJudgmentTransactionFailsTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", false))
      .expect(Pool::balance == 3)
      .expect(Pool::entries.get("A").outcome == "evaluating")

  run shouldSettleOnceWhenFinalizeAndBackfillRepeatTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", -1)).then(Pool::backfill("A", 1))
      .then(Pool::backfill("A", 1)).then(Pool::finalized("A", 1))
      .expect(Pool::balance == 2)
      .expect(Pool::entries.get("A").settlements == 1).expect(Pool::safety)

  run shouldKeepHoldWhenBundlerIsKnownOrUnavailableTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", -1)).then(Pool::expire("A"))
      .then(Pool::sweep("A", "known")).then(Pool::sweep("A", "unavailable"))
      .expect(Pool::balance == 1).expect(not(Pool::entries.get("A").settled))

  run shouldRefundOnceWhenAbandonedHoldIsSweptTwiceTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", -1)).then(Pool::expire("A"))
      .then(Pool::sweep("A", "unknown")).then(Pool::sweep("A", "unknown"))
      .expect(Pool::balance == 3).expect(Pool::safety)

  run shouldRecordUnbackedReplayWhenReleasedSponsorIsRequestedAgainTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", -1)).then(Pool::expire("A"))
      .then(Pool::sweep("A", "unknown")).then(Pool::judge("A", true))
      .expect(not(Pool::replayBackedByFunds)).expect(Pool::safety)

  run shouldSettleInlineWhenPositiveReceiptPrecedesJudgmentTest =
    Pool::init.then(Pool::open("A")).then(Pool::finalized("A", 1))
      .then(Pool::judge("A", true))
      .expect(Pool::entries.get("A").settled).expect(Pool::balance == 2)

  run shouldExposeOrphanWhenZeroReceiptPrecedesJudgmentTest =
    Pool::init.then(Pool::open("A")).then(Pool::finalized("A", 0))
      .then(Pool::judge("A", true)).then(Pool::expire("A"))
      .then(Pool::sweep("A", "unknown")).then(Pool::backfill("A", 0))
      .expect(not(Pool::knownReceiptSettled)).expect(Pool::balance == 1)

  run shouldRefundWhenZeroReceiptFollowsJudgmentTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", 0))
      .expect(Pool::entries.get("A").settled).expect(Pool::balance == 3)

  run shouldSignalReconciliationWhenGasSpikeExceedsPoolTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", 4))
      .expect(Pool::entries.get("A").reconcile)
      .expect(Pool::balance == 1).expect(Pool::safety)

  run shouldSeparateReconciliationFromUnbackedReplayTest =
    Pool::init.then(Pool::open("A")).then(Pool::judge("A", true))
      .then(Pool::finalized("A", 4)).then(Pool::judge("A", true))
      .expect(Pool::entries.get("A").reconcile).expect(Pool::replayBackedByFunds)

  run shouldLeaveBalanceUntouchedWhenChargeIsOnlyPreparedTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::prepare("B"))
      .expect(Charge::balance == 3).expect(Charge::safety)

  run shouldDebitOnceWhenChargeSubmitIsRetriedTest =
    Charge::init.then(Charge::prepare("A"))
      .then(Charge::preflight("A")).then(Charge::submit("A", true)).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .expect(Charge::balance == 1)
      .expect(Charge::entries.get("A").reserves == 1).expect(Charge::safety)

  run shouldRejectConcurrentChargeWhenSharedBalanceIsExhaustedTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::prepare("B"))
      .then(Charge::preflight("A")).then(Charge::submit("A", true)).then(Charge::preflight("B")).then(Charge::submit("B", true))
      .expect(not(Charge::entries.get("B").pending)).expect(Charge::balance == 1)

  run shouldNotDebitWhenChargeIsFrozenOrTransactionFailsTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::setFrozen(true))
      .then(Charge::preflight("A")).then(Charge::submit("A", true)).expect(Charge::balance == 3)
      .then(Charge::setFrozen(false)).then(Charge::preflight("A")).then(Charge::submit("A", false))
      .expect(Charge::balance == 3).expect(Charge::entries.get("A").reserves == 0)

  run shouldRefundOnceWhenChargeSweepIsRetriedTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .then(Charge::expire("A")).then(Charge::sweep("A", "unavailable"))
      .expect(Charge::balance == 1).then(Charge::sweep("A", "unknown"))
      .then(Charge::sweep("A", "unknown"))
      .expect(Charge::balance == 3).expect(Charge::safety)

  run shouldReconcileEstimateWhenReceiptIsCheaperTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .then(Charge::receipt("A", 1)).then(Charge::finalizeSpend("A"))
      .then(Charge::finalizeSpend("A"))
      .expect(Charge::balance == 2).expect(Charge::safety)

  run shouldAbsorbExcessWhenActualCostExceedsUserBalanceTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .then(Charge::receipt("A", 4)).then(Charge::finalizeSpend("A"))
      .expect(Charge::balance == 0)
      .expect(Charge::entries.get("A").absorbed == 1).expect(Charge::safety)

  run shouldDebitRetroactivelyWhenCancelledChargeConfirmsLateTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .then(Charge::expire("A")).then(Charge::sweep("A", "unknown"))
      .then(Charge::receipt("A", 1)).then(Charge::beginRetro("A"))
      .then(Charge::finishRetro("A", true))
      .expect(Charge::balance == 2).expect(Charge::safety)

  run shouldExposeTwoActiveSpendsWhenRetryRacesRetroactiveDebitTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .then(Charge::expire("A")).then(Charge::sweep("A", "unknown"))
      .then(Charge::preflight("A")).then(Charge::receipt("A", 1))
      .then(Charge::beginRetro("A"))
      .then(Charge::submit("A", true)).then(Charge::finishRetro("A", true))
      .expect(not(Charge::oneActiveSpendPerJudgment)).expect(Charge::safety)

  run shouldRollBackWhenRetroactiveTransactionFailsTest =
    Charge::init.then(Charge::prepare("A")).then(Charge::preflight("A")).then(Charge::submit("A", true))
      .then(Charge::expire("A")).then(Charge::sweep("A", "unknown"))
      .then(Charge::receipt("A", 1)).then(Charge::beginRetro("A"))
      .then(Charge::finishRetro("A", false))
      .expect(Charge::balance == 3).expect(not(Charge::entries.get("A").confirmed))

  run shouldNotBurnQuotaWhenPrepareIsAbandonedTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .expect(Quota::counts.get("shared") == 0)

  run shouldEnforceSharedQuotaWhenTwoChainsSubmitTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .then(Quota::prepare("B", "shared", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::lookup("B", 1))
      .then(Quota::commit("A", true)).then(Quota::commit("B", true))
      .expect(Quota::entries.get("B").response == "insufficient")
      .expect(Quota::counts.get("shared") == 1).expect(Quota::safety)

  run shouldClaimOnceWhenSponsorSubmitIsRetriedTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::commit("A", true))
      .then(Quota::lookup("A", 1)).then(Quota::commit("A", true))
      .expect(Quota::entries.get("A").response == "committed")
      .expect(Quota::counts.get("shared") == 1).expect(Quota::safety)

  run shouldIsolateBucketsWhenSponsorsUseIndependentQuotasTest =
    Quota::init.then(Quota::prepare("A", "sponsorA", "sponsor", 1))
      .then(Quota::prepare("B", "sponsorB", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::commit("A", true))
      .then(Quota::lookup("B", 1)).then(Quota::commit("B", true))
      .expect(Quota::counts.get("shared") == 0)
      .expect(Quota::counts.get("sponsorA") == 1)
      .expect(Quota::counts.get("sponsorB") == 1).expect(Quota::safety)

  run shouldRejectStaleIntentWhenReprepareWinsBeforeSubmitLockTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::reprepare("A", "sponsor", 2))
      .then(Quota::commit("A", true))
      .expect(Quota::entries.get("A").response == "insufficient")
      .expect(Quota::counts.get("shared") == 0)

  run shouldRecheckOutcomeWhenReprepareChangesSponsorToChargeTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::reprepare("A", "charge", 1))
      .then(Quota::commit("A", true))
      .expect(Quota::entries.get("A").response == "noop")
      .expect(Quota::counts.get("shared") == 0)

  run shouldFailClosedWhenPolicyDisappearsBeforeSubmitTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::setPolicy("shared", false))
      .then(Quota::commit("A", true))
      .expect(Quota::entries.get("A").response == "insufficient")
      .expect(Quota::counts.get("shared") == 0)

  run shouldRollBackQuotaWhenCommitFailsTest =
    Quota::init.then(Quota::prepare("A", "shared", "sponsor", 1))
      .then(Quota::lookup("A", 1)).then(Quota::commit("A", false))
      .expect(Quota::counts.get("shared") == 0)
      .expect(not(Quota::entries.get("A").slot))
}
