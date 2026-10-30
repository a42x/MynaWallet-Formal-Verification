---
title: Reproducibility
last_updated: 2026-10-30
tags:
  - formal-verification
  - reproducibility
---

# Reproducibility

## Pinned inputs

- Production Solidity source is a git submodule at an exact commit.
- The read-only API authentication snapshot is pinned by
  `verification/auth-source.lock.json`.
- JavaScript dependencies are pinned by `package-lock.json`.
- Non-package-manager tools are recorded in `toolchains.lock.json`.
- Every run captures actual versions and the submodule commit.

## Result classification

- **PASS**: the tool completed and established the stated property within the recorded model and bounds.
- **FAIL**: a counterexample, assertion violation, compilation failure, or non-zero tool exit.
- **SKIP**: a declared prerequisite is absent, such as Kontrol and Docker.
- **UNKNOWN**: timeout, solver unknown, unsupported opcode/cheatcode, bound truncation, or incomplete proof.

`./scripts/verify auth-model` checks the passing authentication safety
conjunctions. `./scripts/verify auth-findings` intentionally evaluates the two
stronger desired properties and exits non-zero while their counterexamples
remain reproducible. Its manifest records those properties as **FAIL**, not as
successful tests.

Every authentication TLC command is capped at 15 minutes, for a total model
checking budget below one hour.

## Updating the target

1. Update `vendor/mynawallet-sc` to the desired commit.
2. Update `toolchains.lock.json`.
3. Run `./scripts/bootstrap`.
4. Run `./scripts/verify full`.
5. Review model assumptions and all implementation harnesses.
6. Commit the submodule pointer, lockfiles, specs, and a redacted evidence summary.
