# Repository Guidelines

## Purpose

This repository contains reproducible formal models and verification harnesses for the MynaWallet cross-chain recovery protocol. The production Solidity repository is pinned as `vendor/mynawallet-sc`; do not edit it here.

## Sources of truth

- Target source revision: `toolchains.lock.json` and the git submodule commit.
- Protocol model: `models/quint/`.
- Implementation properties: `verification/`.
- Reproducible entrypoint: `./scripts/verify`.
- Captured evidence: `results/<run-id>/manifest.txt` and tool logs.

## Rules

- Never silently update the target submodule or a tool version.
- A version update must change `toolchains.lock.json`, lockfiles, and the verification evidence.
- Keep secrets out of logs. In particular, never print `CERTORAKEY` or RPC URLs.
- Distinguish PASS, FAIL, SKIP, and UNKNOWN. A timeout or missing tool is not a pass.
- Every claimed property must be listed in `verification/properties.yaml`.
- Prefer bounded claims with explicit bounds over unqualified claims.
- Run `./scripts/doctor` before verification.
