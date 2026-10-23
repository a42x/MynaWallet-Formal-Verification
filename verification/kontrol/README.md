# Kontrol proofs

Kontrol uses the shared Foundry harness under `verification/solidity`.

Pinned version: `v1.0.255`.

The initial proof target is:

```text
RecoveryHashProperties.test_hashMatchesCanonicalEncoding
```

Run through the repository entrypoint:

```bash
./scripts/verify kontrol
```

The command performs `kontrol build` and then proves the selected test. Any BMC depth introduced later must be recorded in `verification/properties.yaml` and the run manifest.
