---
description: Run the reproducible MynaWallet formal-verification pipeline
argument-hint: "[quick|model|halmos|certora-compile|certora|kontrol|target-test|full]"
allowed-tools: Bash(./scripts/doctor:*), Bash(./scripts/verify:*), Read
---

Run the repository-owned verification entrypoint, not an ad-hoc equivalent.

1. Interpret `$ARGUMENTS` as the profile. Use `quick` when omitted.
2. Run `./scripts/doctor`.
3. Run `./scripts/verify <profile>`.
4. Read the emitted `results/<run-id>/manifest.txt` and relevant logs.
5. Report each stage as PASS, FAIL, SKIP, or UNKNOWN.
6. Include the target submodule commit, exact tool versions, bounds, and evidence paths.
7. Never describe SKIP, timeout, unsupported behavior, or an incomplete proof as PASS.
