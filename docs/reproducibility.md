# Reproducibility

## Pinned inputs

- Production source is a git submodule at an exact commit.
- JavaScript dependencies are pinned by `package-lock.json`.
- Python tools are pinned by `uv.lock`.
- Non-package-manager tools are recorded in `toolchains.lock.json`.
- Every run captures actual versions and the submodule commit.

## Result classification

- **PASS**: the tool completed and established the stated property within the recorded model and bounds.
- **FAIL**: a counterexample, assertion violation, compilation failure, or non-zero tool exit.
- **SKIP**: a declared prerequisite is absent, such as `CERTORAKEY` or Kontrol.
- **UNKNOWN**: timeout, solver unknown, unsupported opcode/cheatcode, bound truncation, or incomplete proof.

## Updating the target

1. Update `vendor/mynawallet-sc` to the desired commit.
2. Update `toolchains.lock.json`.
3. Run `./scripts/bootstrap`.
4. Run `./scripts/verify full`.
5. Review model assumptions and all implementation harnesses.
6. Commit the submodule pointer, lockfiles, specs, and a redacted evidence summary.
