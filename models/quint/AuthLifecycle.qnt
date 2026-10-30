/*
 * Bounded symbolic model of the Myna API passkey authentication lifecycle.
 * Source: a42x/api commit 8277832d744c8ce8e2b191fb06f13bff970babfb.
 * Cryptographic validity, RP-ID/origin checks and unguessable IDs are guards;
 * the model checks authorization, replay and concurrency state transitions.
 */
module AuthRegistration {
  val users = Set("victim", "attacker")
  val requests = Set("victimReq", "attackerReq")

  def requestOwner(req: str): str =
    if (req == "victimReq") "victim" else "attacker"

  var challengeLive: bool
  var requestReadChallenge: str -> bool
  var ekycTokenConsumed: str -> bool
  var registered: str -> bool
  var commitsByIdentity: str -> int
  var successfulRegistrations: int

  action init = all {
    challengeLive' = true,
    requestReadChallenge' = requests.mapBy(_ => false),
    ekycTokenConsumed' = users.mapBy(_ => false),
    registered' = users.mapBy(_ => false),
    commitsByIdentity' = users.mapBy(_ => 0),
    successfulRegistrations' = 0,
  }

  action beginRegistration(req) = all {
    challengeLive,
    not(requestReadChallenge.get(req)),
    not(ekycTokenConsumed.get(requestOwner(req))),
    requestReadChallenge' = requestReadChallenge.set(req, true),
    ekycTokenConsumed' = ekycTokenConsumed.set(requestOwner(req), true),
    challengeLive' = challengeLive,
    registered' = registered,
    commitsByIdentity' = commitsByIdentity,
    successfulRegistrations' = successfulRegistrations,
  }

  /* getRaw() then delete(): a request that already read can commit after a race. */
  action commitRegistration(req) = all {
    requestReadChallenge.get(req),
    not(registered.get(requestOwner(req))),
    challengeLive' = false,
    requestReadChallenge' = requestReadChallenge.set(req, false),
    registered' = registered.set(requestOwner(req), true),
    commitsByIdentity' = commitsByIdentity.setBy(requestOwner(req), n => n + 1),
    successfulRegistrations' = successfulRegistrations + 1,
    ekycTokenConsumed' = ekycTokenConsumed,
  }

  action rollbackRegistration(req) = all {
    requestReadChallenge.get(req),
    not(registered.get(requestOwner(req))),
    requestReadChallenge' = requestReadChallenge.set(req, false),
    ekycTokenConsumed' = ekycTokenConsumed.set(requestOwner(req), false),
    challengeLive' = challengeLive,
    registered' = registered,
    commitsByIdentity' = commitsByIdentity,
    successfulRegistrations' = successfulRegistrations,
  }

  action step = any {
    beginRegistration("victimReq"),
    beginRegistration("attackerReq"),
    commitRegistration("victimReq"),
    commitRegistration("attackerReq"),
    rollbackRegistration("victimReq"),
    rollbackRegistration("attackerReq"),
  }

  val registrationRequiresConsumedEkycToken = users.forall(
    user => registered.get(user) implies ekycTokenConsumed.get(user)
  )
  val onePasskeyCommitPerIdentity = users.forall(
    user => commitsByIdentity.get(user) <= 1
  )
  val committedIdentityIsRegistered = users.forall(
    user => (commitsByIdentity.get(user) == 1) implies registered.get(user)
  )
  val safety =
    registrationRequiresConsumedEkycToken and
      onePasskeyCommitPerIdentity and committedIdentityIsRegistered

  /* Expected counterexample under two concurrent verify requests. */
  val registrationChallengeSingleUse = successfulRegistrations <= 1
}

module AuthLogin {
  val users = Set("victim", "attacker")
  val MaxRequestsPerEndpoint: int = 2
  val unifiedFailure: str = "login_failed"

  var challengeLive: bool
  var challengeGeneration: int
  var challengeUses: int
  var optionsAccepted: int
  var verifyAccepted: int
  var sessionsIssued: int
  var lastSessionOwner: str
  var lastAnonymousResponse: str

  action init = all {
    challengeLive' = false,
    challengeGeneration' = 0,
    challengeUses' = 0,
    optionsAccepted' = 0,
    verifyAccepted' = 0,
    sessionsIssued' = 0,
    lastSessionOwner' = "none",
    lastAnonymousResponse' = "none",
  }

  action requestOptions = all {
    optionsAccepted < MaxRequestsPerEndpoint,
    not(challengeLive),
    challengeLive' = true,
    challengeGeneration' = challengeGeneration + 1,
    challengeUses' = 0,
    optionsAccepted' = optionsAccepted + 1,
    verifyAccepted' = verifyAccepted,
    sessionsIssued' = sessionsIssued,
    lastSessionOwner' = lastSessionOwner,
    lastAnonymousResponse' = lastAnonymousResponse,
  }

  /* kind is unknown_credential, bad_assertion, counter_anomaly or valid. */
  action verify(kind, user) = all {
    challengeLive,
    verifyAccepted < MaxRequestsPerEndpoint,
    challengeLive' = false,
    challengeUses' = challengeUses + 1,
    verifyAccepted' = verifyAccepted + 1,
    if (kind == "valid") {
      all {
        users.contains(user),
        sessionsIssued' = sessionsIssued + 1,
        lastSessionOwner' = user,
        lastAnonymousResponse' = lastAnonymousResponse,
      }
    } else {
      all {
        sessionsIssued' = sessionsIssued,
        lastSessionOwner' = lastSessionOwner,
        lastAnonymousResponse' = unifiedFailure,
      }
    },
    challengeGeneration' = challengeGeneration,
    optionsAccepted' = optionsAccepted,
  }

  action optionsRateLimited = all {
    optionsAccepted >= MaxRequestsPerEndpoint,
    lastAnonymousResponse' = "rate_limited",
    challengeLive' = challengeLive,
    challengeGeneration' = challengeGeneration,
    challengeUses' = challengeUses,
    optionsAccepted' = optionsAccepted,
    verifyAccepted' = verifyAccepted,
    sessionsIssued' = sessionsIssued,
    lastSessionOwner' = lastSessionOwner,
  }

  action verifyRateLimited = all {
    verifyAccepted >= MaxRequestsPerEndpoint,
    lastAnonymousResponse' = "rate_limited",
    challengeLive' = challengeLive,
    challengeGeneration' = challengeGeneration,
    challengeUses' = challengeUses,
    optionsAccepted' = optionsAccepted,
    verifyAccepted' = verifyAccepted,
    sessionsIssued' = sessionsIssued,
    lastSessionOwner' = lastSessionOwner,
  }

  action step = any {
    requestOptions,
    verify("unknown_credential", "none"),
    verify("bad_assertion", "none"),
    verify("counter_anomaly", "none"),
    verify("valid", "victim"),
    verify("valid", "attacker"),
    optionsRateLimited,
    verifyRateLimited,
  }

  val loginChallengeConsumedAtMostOnce = challengeUses <= 1
  val loginRequiresGeneratedChallenge =
    sessionsIssued <= challengeGeneration and sessionsIssued <= verifyAccepted
  val sessionOwnerIsRegisteredIdentity =
    (lastSessionOwner == "none") or users.contains(lastSessionOwner)
  val anonymousFailuresAreIndistinguishable = unifiedFailure == "login_failed"
  val rateLimitsHold =
    optionsAccepted <= MaxRequestsPerEndpoint and
      verifyAccepted <= MaxRequestsPerEndpoint
  val safety =
    loginChallengeConsumedAtMostOnce and loginRequiresGeneratedChallenge and
      sessionOwnerIsRegisteredIdentity and anonymousFailuresAreIndistinguishable and
      rateLimitsHold
}

module AuthSession {
  val users = Set("victim", "attacker")
  val refreshTokens = Set("R1", "R2", "R3")
  val accessTokens = Set("A1", "A2", "A3")
  val AccessTtl: int = 2
  val MaxTicks: int = 4

  var refreshState: str -> str
  var refreshOwner: str -> str
  var refreshUses: str -> int
  var accessState: str -> str
  var accessOwner: str -> str
  var accessExpiresAt: str -> int
  var clock: int
  var recovered: str -> bool
  var deleted: str -> bool
  var loggedOut: str -> bool
  var foreignLogoutProtected: bool
  var accessUsedAfterTermination: bool

  action init = all {
    refreshState' = refreshTokens.mapBy(t => if (t == "R3") "unused" else "active"),
    refreshOwner' = refreshTokens.mapBy(t =>
      if (t == "R1") "victim" else if (t == "R2") "attacker" else "none"
    ),
    refreshUses' = refreshTokens.mapBy(_ => 0),
    accessState' = accessTokens.mapBy(t => if (t == "A3") "unused" else "active"),
    accessOwner' = accessTokens.mapBy(t =>
      if (t == "A1") "victim" else if (t == "A2") "attacker" else "none"
    ),
    accessExpiresAt' = accessTokens.mapBy(t => if (t == "A3") 0 else AccessTtl),
    clock' = 0,
    recovered' = users.mapBy(_ => false),
    deleted' = users.mapBy(_ => false),
    loggedOut' = users.mapBy(_ => false),
    foreignLogoutProtected' = true,
    accessUsedAfterTermination' = false,
  }

  action refresh(oldToken, newToken, newAccess) = all {
    refreshState.get(oldToken) == "active",
    refreshState.get(newToken) == "unused",
    accessState.get(newAccess) == "unused",
    not(recovered.get(refreshOwner.get(oldToken))),
    not(deleted.get(refreshOwner.get(oldToken))),
    refreshState' = refreshState.set(oldToken, "revoked").set(newToken, "active"),
    refreshOwner' = refreshOwner.set(newToken, refreshOwner.get(oldToken)),
    refreshUses' = refreshUses.setBy(oldToken, count => count + 1),
    accessState' = accessState.set(newAccess, "active"),
    accessOwner' = accessOwner.set(newAccess, refreshOwner.get(oldToken)),
    accessExpiresAt' = accessExpiresAt.set(newAccess, clock + AccessTtl),
    clock' = clock,
    recovered' = recovered,
    deleted' = deleted,
    loggedOut' = loggedOut,
    foreignLogoutProtected' = foreignLogoutProtected,
    accessUsedAfterTermination' = accessUsedAfterTermination,
  }

  /* The route rejects a foreign owner and otherwise revokes the refresh token. */
  action logout(user, token) = all {
    refreshState.get(token) == "active",
    if (refreshOwner.get(token) == user) {
      all {
        refreshState' = refreshState.set(token, "revoked"),
        loggedOut' = loggedOut.set(user, true),
        foreignLogoutProtected' = foreignLogoutProtected,
      }
    } else {
      all {
        refreshState' = refreshState,
        loggedOut' = loggedOut,
        foreignLogoutProtected' = refreshState.get(token) == "active",
      }
    },
    refreshOwner' = refreshOwner,
    refreshUses' = refreshUses,
    accessState' = accessState,
    accessOwner' = accessOwner,
    accessExpiresAt' = accessExpiresAt,
    clock' = clock,
    recovered' = recovered,
    deleted' = deleted,
    accessUsedAfterTermination' = accessUsedAfterTermination,
  }

  action terminate(kind, user) = all {
    if (kind == "recovery") {
      all { not(recovered.get(user)), recovered' = recovered.set(user, true), deleted' = deleted }
    } else {
      all { not(deleted.get(user)), deleted' = deleted.set(user, true), recovered' = recovered }
    },
    refreshState' = refreshTokens.mapBy(token =>
      if (refreshOwner.get(token) == user and refreshState.get(token) == "active")
        "revoked"
      else refreshState.get(token)
    ),
    refreshOwner' = refreshOwner,
    refreshUses' = refreshUses,
    accessState' = accessState,
    accessOwner' = accessOwner,
    accessExpiresAt' = accessExpiresAt,
    clock' = clock,
    loggedOut' = loggedOut,
    foreignLogoutProtected' = foreignLogoutProtected,
    accessUsedAfterTermination' = accessUsedAfterTermination,
  }

  action tick = all {
    clock < MaxTicks,
    clock' = clock + 1,
    accessState' = accessTokens.mapBy(token =>
      if (accessState.get(token) == "active" and accessExpiresAt.get(token) <= clock + 1)
        "expired"
      else accessState.get(token)
    ),
    refreshState' = refreshState,
    refreshOwner' = refreshOwner,
    refreshUses' = refreshUses,
    accessOwner' = accessOwner,
    accessExpiresAt' = accessExpiresAt,
    recovered' = recovered,
    deleted' = deleted,
    loggedOut' = loggedOut,
    foreignLogoutProtected' = foreignLogoutProtected,
    accessUsedAfterTermination' = accessUsedAfterTermination,
  }

  action useAccessAfterTermination(token) = all {
    accessState.get(token) == "active",
    loggedOut.get(accessOwner.get(token)) or recovered.get(accessOwner.get(token)),
    accessUsedAfterTermination' = true,
    refreshState' = refreshState,
    refreshOwner' = refreshOwner,
    refreshUses' = refreshUses,
    accessState' = accessState,
    accessOwner' = accessOwner,
    accessExpiresAt' = accessExpiresAt,
    clock' = clock,
    recovered' = recovered,
    deleted' = deleted,
    loggedOut' = loggedOut,
    foreignLogoutProtected' = foreignLogoutProtected,
  }

  action step = any {
    refresh("R1", "R3", "A3"),
    refresh("R2", "R3", "A3"),
    logout("victim", "R1"),
    logout("attacker", "R1"),
    logout("attacker", "R2"),
    logout("victim", "R2"),
    logout("victim", "R3"),
    logout("attacker", "R3"),
    terminate("recovery", "victim"),
    terminate("recovery", "attacker"),
    terminate("deletion", "victim"),
    terminate("deletion", "attacker"),
    tick,
    useAccessAfterTermination("A1"),
    useAccessAfterTermination("A2"),
    useAccessAfterTermination("A3"),
  }

  val refreshRotatesAtMostOnce = refreshTokens.forall(t => refreshUses.get(t) <= 1)
  val activeRefreshHasOwner = refreshTokens.forall(t =>
    (refreshState.get(t) == "active") implies users.contains(refreshOwner.get(t))
  )
  val terminatedAccountsHaveNoRefresh = users.forall(user =>
    (recovered.get(user) or deleted.get(user)) implies refreshTokens.forall(t =>
      (refreshOwner.get(t) == user) implies refreshState.get(t) != "active"
    )
  )
  val activeAccessIsUnexpired = accessTokens.forall(t =>
    (accessState.get(t) == "active") implies accessExpiresAt.get(t) > clock
  )
  val activeAccessHasOwner = accessTokens.forall(t =>
    (accessState.get(t) == "active") implies users.contains(accessOwner.get(t))
  )
  val safety =
    refreshRotatesAtMostOnce and activeRefreshHasOwner and
      terminatedAccountsHaveNoRefresh and activeAccessIsUnexpired and
      activeAccessHasOwner and foreignLogoutProtected

  /* Expected counterexample: stateless access JWTs survive until expiry. */
  val immediateAccessInvalidation = not(accessUsedAfterTermination)
}

module AuthLifecycleTests {
  import AuthRegistration as Registration
  import AuthLogin as Login
  import AuthSession as Session

  run concurrentRegistrationChallengeReuseTest =
    Registration::init
      .then(Registration::beginRegistration("victimReq"))
      .then(Registration::beginRegistration("attackerReq"))
      .then(Registration::commitRegistration("victimReq"))
      .then(Registration::commitRegistration("attackerReq"))
      .expect(Registration::successfulRegistrations == 2)

  run registrationRollbackRestoresEkycTokenTest =
    Registration::init
      .then(Registration::beginRegistration("victimReq"))
      .then(Registration::rollbackRegistration("victimReq"))
      .expect(not(Registration::ekycTokenConsumed.get("victim")))

  run anonymousLoginErrorsAreUnifiedTest =
    Login::init
      .then(Login::requestOptions)
      .then(Login::verify("unknown_credential", "none"))
      .expect(Login::lastAnonymousResponse == "login_failed")

  run loginChallengeIsConsumedTest =
    Login::init
      .then(Login::requestOptions)
      .then(Login::verify("valid", "victim"))
      .expect(Login::challengeUses == 1)
      .expect(not(Login::challengeLive))

  run refreshRotationRevokesOldTokenTest =
    Session::init
      .then(Session::refresh("R1", "R3", "A3"))
      .expect(Session::refreshState.get("R1") == "revoked")
      .expect(Session::refreshOwner.get("R3") == "victim")

  run foreignLogoutCannotRevokeTest =
    Session::init
      .then(Session::logout("attacker", "R1"))
      .expect(Session::refreshState.get("R1") == "active")

  run recoveryRevokesRefreshTokensTest =
    Session::init
      .then(Session::terminate("recovery", "victim"))
      .expect(Session::refreshState.get("R1") == "revoked")

  run accessTokenSurvivesLogoutUntilExpiryTest =
    Session::init
      .then(Session::logout("victim", "R1"))
      .then(Session::useAccessAfterTermination("A1"))
      .expect(Session::accessUsedAfterTermination)
      .then(Session::tick)
      .then(Session::tick)
      .expect(Session::accessState.get("A1") == "expired")
}
