---
title: Myna API authentication lifecycle model-checking report
last_updated: 2026-10-30
tags:
  - authentication
  - formal-verification
  - passkeys
  - quint
  - security
---

# Myna API authentication lifecycle model-checking report

## 対象

- API source: `a42x/api`
- Branch: `develop`
- Commit: `8277832d744c8ce8e2b191fb06f13bff970babfb`
- Lock: `verification/auth-source.lock.json`
- Model: `models/quint/AuthLifecycle.qnt`
- Tool: Quint 0.33.0 + TLC

対象はメール・パスワード認証ではなく、eKYC session token、WebAuthn
passkey、access/refresh JWTによる認証ライフサイクルである。

## 脅威モデル

攻撃者は公開APIを任意順序・並行で呼び出し、識別子と応答を観測し、
漏えい済みrefresh tokenを再利用できる。TLS、JWT/WebAuthn署名、RP-ID・
origin検証、乱数生成、メール・JPKI基盤そのものの破壊は対象外とした。

暗号処理は記号化し、状態遷移、所有者の混同、single-use、rotation、
replay、logout/recoveryとの競合を検査した。

## 結果

| Property group | Result | Explored state graph |
|---|---:|---:|
| Registration safety (`AUTH-REG-001..002`) | PASS | 9 states, depth 5 |
| Login safety (`AUTH-LOGIN-001..004`) | PASS | 21 states, depth 6 |
| Session safety (`AUTH-SESSION-001..005`) | PASS | 4,340 states, depth 13 |
| Registration challenge strict single-use (`AUTH-REG-CE-001`) | FAIL | counterexample at depth 5 |
| Immediate access-token invalidation (`AUTH-SESSION-CE-001`) | FAIL | counterexample at depth 6 |

PASSは記載した有限境界と抽象化の範囲だけを意味する。FAILはタイムアウト
ではなく、TLCが具体的な到達トレースを生成した結果である。

## Finding 1: registration challengeの並行再利用

**結果: FAIL / 推奨優先度: Medium**

登録検証はchallengeを`getRaw()`で読み、WebAuthn検証後に`delete()`する。
read-and-deleteがatomicではないため、2リクエストが削除前に同じchallengeを
読み終えると、先行リクエストの削除後も両方がcommitできる。

反例:

1. victim requestがchallengeを読む。
2. attacker requestも同じchallengeを読む。
3. victim requestが登録をcommitしてchallengeを削除する。
4. attacker requestも既に読んだchallengeで登録をcommitする。

各リクエストには依然として有効なeKYC tokenとWebAuthn responseが必要であり、
この反例単独で他人のアカウントへログインできるわけではない。ただし、
challengeのsingle-use保証とceremony間の分離は成立しない。またchallengeに
保存した`jpkiUserId`と、verify時のeKYC token `sub`の一致確認も行われていない。

推奨修正:

- loginと同様に、registration challengeもverify開始時にatomic consumeする。
- consumed challengeの`jpkiUserId`とeKYC tokenの`sub`を必ず照合する。
- 2つの並行verifyのうち1つだけが成功するDB/Redis統合テストを追加する。

## Finding 2: logout/recovery後もaccess JWTが期限まで有効

**結果: FAIL / 推奨優先度: Medium（明示された設計上の制約）**

logout、recovery、account deletionはrefresh tokenをserver-sideで失効させるが、
access tokenは署名だけで検証されるstateless JWTである。logout/recovery前に
発行されたaccess tokenは、既定値では最大900秒、引き続き利用できる。
account deletionだけはDB参照による追加拒否があるが、DB障害時はfail-openである。

推奨修正は、要求するtermination保証に応じて次のいずれかである。

- 高リスクAPIでsession epochまたはcredential versionを照合する。
- access-token JTI denylistを短いTTLで保持する。
- 即時失効を要求しない場合は、900秒の残存リスクを仕様・ASVS評価に明記し、
  重要操作で再認証を要求する。

## 成立した主な性質

- eKYC token markerはatomicにsingle-use化され、pre-commit rollbackは所有者値を
  比較して自分のmarkerだけを削除する。
- login challengeはverify開始時にatomic consumeされ、失敗時も再利用できない。
- unknown credential、invalid assertion、counter anomalyは同じ匿名エラーになる。
- refresh rotationは旧tokenのconsumeと新token insertを同一transactionで行い、
  同じ旧tokenから成功するrotationは1回だけである。
- logoutは認証済みcallerとrefresh-token ownerが一致する場合だけ失効させる。
- recovery/deletionは対象identityのactive refresh tokenを全て失効させる。
- token rotationでidentity ownerは変化しない。

## 境界と未証明事項

- identityは2、registration requestは2、refresh/access tokenは各3。
- rate limitは1 IP、options/verify別bucket、各2回へ縮約した。
- 列挙耐性はresponse classの一致のみ。timing、payload size、ログなどは未証明。
- IP rotation、botnet、Redis/DBの長時間障害は未証明。
- WebAuthn library、JWT library、鍵管理、端末authenticatorの実装正当性は仮定。
- password resetは対象APIに存在しない。passkey recoveryのchain側性質は既存の
  `CrossChainRecovery.qnt`が補完する。

## 再現

```bash
./scripts/doctor
./scripts/verify auth-model
./scripts/verify auth-findings
```

`auth-model`はPASSする安全性conjunctionを検査する。`auth-findings`は上記2性質を
検査し、counterexampleを記録して非0終了する。
