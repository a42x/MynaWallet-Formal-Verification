# Kontrol proofs

Kontrol uses the shared Foundry harness under `verification/solidity`.

Pinned version: `v1.0.255`.

The initial proof targets are:

```text
RecoveryHashProperties.test_hashMatchesCanonicalEncoding
PaymasterProperties.*            # gas-sponsor (verifying paymaster) API
```

The paymaster suite verifies the ERC-4337 sponsor API of
`vendor/mynawallet-sc/src/core/MynaWalletPaymaster.sol` through
`src/PaymasterHarness.sol` (property list: `PAY-KONTROL-001..008` in
`verification/properties.yaml`). Because the harness imports target code
whose imports resolve under the vendor project root, `src/` in
`verification/solidity` carries relative symlinks into the vendor source
tree and `foundry.toml` adds the vendor `@libraries`/`@interfaces`/`@core`/
`@common` remappings. Do not edit files under those symlinks.

Run through the repository entrypoint:

```bash
./scripts/install-kontrol   # optional pre-pull of the pinned Docker image
./scripts/verify kontrol
```

The runner uses a local `kontrol` binary when available. Otherwise it runs the official image pinned by digest in `toolchains.lock.json`. On constrained Docker and CI runners, the LLVM helper and Haskell definition are kompiled sequentially to avoid an out-of-memory failure; the generated definitions are otherwise unchanged.

The command performs `kontrol build -O0` and then proves the selected tests.
Any BMC depth introduced later must be recorded in `verification/properties.yaml` and the run manifest.

Proof-authoring constraints:

- The `assertEq` comparison of returned dynamic `bytes` (e.g. the sponsor
  context) crashes the KORE server during proof exploration. Use
  `keccak256`-based comparisons for dynamic-bytes equality; scalar
  `validationData` comparisons are safe.
- Stateful properties are concrete bounded runs; only the digest and the
  TTL/encoding-gate tests take symbolic parameters, as recorded in the
  `bounds` fields of `verification/properties.yaml`.
