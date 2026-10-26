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
| Off-chain model | Quint + TLC | API/relayer/guardian 同期:重複送信禁止、署名 deadline、quorum、terminal 状態不変、cooldown、通知冪等性 |
| Implementation tests | Foundry | Solidityテスト形式での反例探索・E2E |
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
./scripts/verify kontrol
./scripts/verify target-test
./scripts/verify full
```

Kontrolはローカルインストールがあればそれを使用し、なければdigest固定の公式Dockerイメージを使用します。

```bash
./scripts/install-kontrol   # pinned Docker imageを事前取得
./scripts/verify kontrol
```

Apple Siliconでは公式amd64イメージをDockerのエミュレーションで実行します。メモリ制約のあるrunner向けに、LLVM helperとHaskell definitionのkompileを順次実行します。

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

最後のskillはbuild、Foundry test、deploy dry-run、fork/parity検査用であり、Kontrol・Quintによる形式検証ではありません。

## 信頼境界

検証結果は次に依存します。

- pinned Solidity sourceと依存関係
- compiler/tool versions
- Kontrolの探索bound
- Quintモデルが実装・運用を正しく抽象化していること

Off-chainレイヤー(`CCR-API-001..005`、`CCR-REL-001/002`)は `a42x/api` の recovery feature と
`a42x/api-infrastructure` の recovery-relayer/guardian2 を対象に、次の抽象を置いて検証している:

- Guardian 1 は API プロセス内 KMS 署名、Guardian 2 は nft-cosigner-template Cloud Run サービスからの
  HTTP フェッチ。双方を boolean availability に抽象化する。
- オンチェーンの guardian-approval deadline(TYPEHASH)は submit ガード `not deadlinePassed` としてモデル化し、
  実装層(Kontrol / Foundry)で裏付けを取る。
- dispatch -> (deliver | lose) -> submit でリレー送信と chain 取り込みを抽象化する。

cross-chain relayer、chain finality については明示したassumptionを引き続き置く。

詳細は [docs/methodology.md](docs/methodology.md) を参照してください。
