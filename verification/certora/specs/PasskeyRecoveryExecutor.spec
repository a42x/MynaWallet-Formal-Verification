/*
 * CCR-CERTORA-001
 *
 * Once a recovery request is consumed, no successful public method may make it
 * unconsumed again. Reverting paths are excluded by CVL rule semantics.
 */
methods {
    function consumedRecoveryRequests(bytes16) external returns (bool) envfree;
}

rule consumedRecoveryRequestIsMonotonic(
    method f,
    env e,
    calldataarg args,
    bytes16 requestId
) {
    bool consumedBefore = consumedRecoveryRequests(requestId);

    f(e, args);

    bool consumedAfter = consumedRecoveryRequests(requestId);
    assert consumedBefore => consumedAfter,
        "a consumed recovery request must never become reusable";
}
