# MynaWallet Formal Verification

`MynaWallet-SC` の `feat/cross-chain-recovery` を対象にした、独立した形式検証リポジトリです。

## 対象

- Source: [a42x/MynaWallet-SC](https://github.com/a42x/MynaWallet-SC)
- Branch at creation: `feat/cross-chain-recovery`
- Pinned commit: `357027d4b7e04ee6fd5cfca913bc1acfd1a30392`

対象コードは `vendor/mynawallet-sc` git submoduleとして固定します。

## 検証レイヤー

| レイヤー | ツール | 目的 |
|---|---|---|
| Protocol model | Quint + TLC/Apalache | 複数chain、fan-out、遅延、重複、状態不一致 |
| Contract invariants | Certora | replay、threshold、atomicity、state cleanup |
| Symbolic tests | Halmos | Solidityテスト形式での反例探索 |
| EVM semantics | Kontrol/KEVM | EntryPoint、EIP-7702、proxy、delegatecall、rollback |

## 再現可能な入口

```bash
./scripts/bootstrap
./scripts/doctor
./scripts/verify quick
```

プロファイル:

```bash
./scripts/verify model
./scripts/verify halmos
./scripts/verify certora-compile
./scripts/verify certora       # CERTORAKEY required
./scripts/verify kontrol
./scripts/verify target-test
./scripts/verify full
```

すべての実行は `results/<UTC timestamp>-<git sha>/` に次を保存します。

- 対象source commit
- tool versions
- 実行コマンド
- exit code
- stdout/stderr
- PASS / FAIL / SKIP / UNKNOWN

## Claude Code

`.claude/commands/verification.md` に `/verification` コマンドを定義しています。

例:

```text
/verification quick
/verification model
/verification full
```

## 既存コマンドの調査結果

元のMynaWallet-SCおよび `feat/cross-chain-recovery` には、Claude Code用の形式検証コマンドはありませんでした。

存在していたもの:

- `.claude/commands/solidity-quality.md`
- `.claude/commands/solidity-security.md`
- `.cursor/skills/verify-mynawallet-sc/SKILL.md`

最後のskillはbuild、Foundry test、deploy dry-run、fork/parity検査用であり、Certora・Kontrol・Halmos・Quintによる形式検証ではありません。

## 信頼境界

検証結果は次に依存します。

- pinned Solidity sourceと依存関係
- compiler/tool versions
- Certoraのexternal-call summaries
- Halmos/Kontrolの探索bound
- Quintモデルが実装・運用を正しく抽象化していること
- cross-chain relayer、chain finality、guardian同期について明示したassumption

詳細は [docs/methodology.md](docs/methodology.md) を参照してください。
