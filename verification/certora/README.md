# Certora

The initial CVL property proves monotonicity of `consumedRecoveryRequests` across every successful public method invocation.

Local reproducibility gate:

```bash
./scripts/verify certora-compile
```

This compiles the pinned Solidity source and type-checks the CVL request locally without submitting a proof.

Remote proof:

```bash
export CERTORAKEY=...
./scripts/verify certora
```

The API key value must never be written to logs or committed. External-call summaries and loop settings are part of the proof model and must be reviewed before interpreting a PASS.
