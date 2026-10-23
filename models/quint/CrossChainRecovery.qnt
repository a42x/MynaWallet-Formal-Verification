/*
 * Abstract protocol model for MynaWallet chain-id-less recovery fan-out.
 *
 * This model intentionally abstracts cryptography to a boolean configuration-validity
 * condition. Solidity-level tools verify the digest and signature-processing code.
 */
module CrossChainRecovery {
  val InitialKey: int = 1
  val RequestedKey: int = 2

  var deliveredA: bool
  var deliveredB: bool
  var consumedA: bool
  var consumedB: bool
  var executionsA: int
  var executionsB: int
  var keyA: int
  var keyB: int
  var pausedA: bool
  var pausedB: bool
  var configFreshA: bool
  var configFreshB: bool

  action init = all {
    deliveredA' = false,
    deliveredB' = false,
    consumedA' = false,
    consumedB' = false,
    executionsA' = 0,
    executionsB' = 0,
    keyA' = InitialKey,
    keyB' = InitialKey,
    pausedA' = false,
    pausedB' = false,
    configFreshA' = true,
    configFreshB' = true,
  }

  action deliverA = all {
    not(deliveredA),
    deliveredA' = true,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action deliverB = all {
    not(deliveredB),
    deliveredA' = deliveredA,
    deliveredB' = true,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action submitA = all {
    deliveredA,
    not(consumedA),
    not(pausedA),
    configFreshA,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = true,
    consumedB' = consumedB,
    executionsA' = executionsA + 1,
    executionsB' = executionsB,
    keyA' = RequestedKey,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action submitB = all {
    deliveredB,
    not(consumedB),
    not(pausedB),
    configFreshB,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = true,
    executionsA' = executionsA,
    executionsB' = executionsB + 1,
    keyA' = keyA,
    keyB' = RequestedKey,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action replayRejectedA = all {
    consumedA,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action replayRejectedB = all {
    consumedB,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action pauseA = all {
    not(pausedA),
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = true,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action unpauseA = all {
    pausedA,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = false,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action pauseB = all {
    not(pausedB),
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = true,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action unpauseB = all {
    pausedB,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = false,
    configFreshA' = configFreshA,
    configFreshB' = configFreshB,
  }

  action rotateA = all {
    configFreshA,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = false,
    configFreshB' = configFreshB,
  }

  action rotateB = all {
    configFreshB,
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = false,
  }

  action reconcileA = all {
    not(configFreshA),
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = true,
    configFreshB' = configFreshB,
  }

  action reconcileB = all {
    not(configFreshB),
    deliveredA' = deliveredA,
    deliveredB' = deliveredB,
    consumedA' = consumedA,
    consumedB' = consumedB,
    executionsA' = executionsA,
    executionsB' = executionsB,
    keyA' = keyA,
    keyB' = keyB,
    pausedA' = pausedA,
    pausedB' = pausedB,
    configFreshA' = configFreshA,
    configFreshB' = true,
  }

  action step = any {
    deliverA,
    deliverB,
    submitA,
    submitB,
    replayRejectedA,
    replayRejectedB,
    pauseA,
    unpauseA,
    pauseB,
    unpauseB,
    rotateA,
    rotateB,
    reconcileA,
    reconcileB,
  }

  val atMostOncePerChain =
    executionsA >= 0 and executionsA <= 1 and
    executionsB >= 0 and executionsB <= 1

  val consumedExactlyWhenExecuted =
    (consumedA == (executionsA == 1)) and
    (consumedB == (executionsB == 1))

  val executionInstallsRequestedKey =
    ((executionsA == 1) implies (keyA == RequestedKey)) and
    ((executionsB == 1) implies (keyB == RequestedKey))

  val noMutationBeforeExecution =
    ((executionsA == 0) implies (keyA == InitialKey)) and
    ((executionsB == 0) implies (keyB == InitialKey))

  val samePayloadConverges =
    ((executionsA == 1 and executionsB == 1) implies (keyA == keyB))

  val safety =
    atMostOncePerChain and
    consumedExactlyWhenExecuted and
    executionInstallsRequestedKey and
    noMutationBeforeExecution and
    samePayloadConverges
}

module CrossChainRecoveryTests {
  import CrossChainRecovery.*

  run fanoutSuccessTest =
    init
      .then(deliverA)
      .then(deliverB)
      .then(submitA)
      .then(submitB)
      .expect(executionsA == 1)
      .expect(executionsB == 1)
      .expect(keyA == RequestedKey)
      .expect(keyB == RequestedKey)

  run replayIsRejectedTest =
    init
      .then(deliverA)
      .then(submitA)
      .then(replayRejectedA)
      .expect(executionsA == 1)

  run staleConfigCausesPartialRecoveryTest =
    init
      .then(deliverA)
      .then(deliverB)
      .then(rotateB)
      .then(submitA)
      .expect(executionsA == 1)
      .expect(executionsB == 0)
      .expect(configFreshB == false)

  run reconcileAllowsDelayedRecoveryTest =
    init
      .then(deliverB)
      .then(rotateB)
      .then(reconcileB)
      .then(submitB)
      .expect(executionsB == 1)

  run pauseBlocksUntilUnpausedTest =
    init
      .then(deliverA)
      .then(pauseA)
      .then(unpauseA)
      .then(submitA)
      .expect(executionsA == 1)
}
