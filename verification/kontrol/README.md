# Kontrol proofs

Kontrol uses the shared Foundry harness under `verification/solidity`.

Pinned version: `v1.0.255`.

The initial proof target is:

```text
RecoveryHashProperties.test_hashMatchesCanonicalEncoding
```

Run through the repository entrypoint:

```bash
./scripts/install-kontrol   # optional pre-pull of the pinned Docker image
./scripts/verify kontrol
```

The runner uses a local `kontrol` binary when available. Otherwise it runs the official image pinned by digest in `toolchains.lock.json`. On constrained Docker and CI runners, the LLVM helper and Haskell definition are kompiled sequentially to avoid an out-of-memory failure; the generated definitions are otherwise unchanged.

The command performs `kontrol build -O0` and then proves the selected test. Any BMC depth introduced later must be recorded in `verification/properties.yaml` and the run manifest.
