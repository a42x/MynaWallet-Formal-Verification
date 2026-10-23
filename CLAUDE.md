# MynaWallet Formal Verification

Use `./scripts/verify` as the only orchestration entrypoint. Do not invent ad-hoc commands when recording evidence.

The target implementation is the pinned submodule `vendor/mynawallet-sc` at the commit recorded in `toolchains.lock.json`.

Claude Code command:

- `/verification quick`
- `/verification model`
- `/verification halmos`
- `/verification certora-compile`
- `/verification certora`
- `/verification kontrol`
- `/verification full`

Before reporting a property as verified, inspect the generated `results/<run-id>/manifest.txt` and logs. Missing credentials, missing tools, bounds reached, solver timeout, and unsupported instructions must be reported as SKIP or UNKNOWN, never PASS.
