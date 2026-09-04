# Phase 4-2 — Lambda + SNS サイト死活監視

**AWS 三層アーキテクチャ実習 / Cloud Ops Lab**

| 項目 | 内容 |
|---|---|
| 実施日 | 2026-09-02 |
| リージョン | ap-northeast-1 |
| 結果 | 完成・end-to-end検証済み（スケジュール実行でメール通知を確認） |

---

## 目標

WordPressサイトに定期的にHTTPリクエストを送り、応答が無ければメールで通知する仕組みを、Lambda + SNS で作る。サーバーを常時見張るのではなく「タイマーで叩いて、ダメなら知らせる」という**サーバーレスの死活監視**を体験するのが狙い。

---

## 構成

```
EventBridge (rate(5 minutes))
      │ 5分ごとに起動
      ▼
Lambda: cloud-ops-lab-site-monitor
  (Python / arm64 / urllib で GET)
      │ 応答なし・200以外なら sns.publish
      ▼
SNS トピック: cloud-ops-lab-site-alert
      │
      ▼
メール通知（確認済みの購読先へ）
```

| 役割 | リソース |
|---|---|
| タイマー | EventBridge ルール `cloud-ops-lab-site-monitor-5min` = `rate(5 minutes)` |
| 監視ロジック | Lambda `cloud-ops-lab-site-monitor`（Python, arm64, タイムアウト20秒） |
| 通知の受け口 | SNS トピック `cloud-ops-lab-site-alert`（Eメール購読・確認済み） |
| 権限 | Lambda実行ロール = `AWSLambdaBasicExecution`（ログ）+ インライン `sns:Publish` |

---

## Lambda コード（標準ライブラリのみ・パッケージ不要）

```python
import os
import urllib.request
import urllib.error
import boto3

SITE_URL  = os.environ["SITE_URL"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
TIMEOUT   = int(os.environ.get("TIMEOUT", "10"))

sns = boto3.client("sns")

def lambda_handler(event, context):
    try:
        req = urllib.request.Request(SITE_URL, method="GET")
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            status = res.status
        if status == 200:
            print(f"OK: {SITE_URL} returned {status}")
            return {"ok": True, "status": status}
        reason = f"HTTP {status}"
    except urllib.error.HTTPError as e:
        reason = f"HTTP {e.code}"
    except Exception as e:
        reason = f"{type(e).__name__}: {e}"

    msg = (f"[ALERT] サイト監視 異常検知\n"
           f"URL: {SITE_URL}\n"
           f"理由: {reason}")
    print(msg)
    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject="[Cloud Ops Lab] サイト応答なし",
        Message=msg,
    )
    return {"ok": False, "reason": reason}
```

**環境変数**

| キー | 値 |
|---|---|
| `SITE_URL` | `http://13.196.53.206/` |
| `TOPIC_ARN` | `arn:aws:sns:ap-northeast-1:205382053604:cloud-ops-lab-site-alert` |
| `TIMEOUT` | `10` |

**SNS発行のインラインポリシー**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sns:Publish",
    "Resource": "arn:aws:sns:ap-northeast-1:205382053604:cloud-ops-lab-site-alert"
  }]
}
```

---

## 手順ログ

### Step 1. SNSトピック + メール購読
- スタンダードトピック `cloud-ops-lab-site-alert` を作成
- Eメール購読を作成 → 届いた確認メールの **Confirm subscription** をクリック → ステータス「確認済み」

### Step 2. Lambda関数
- `cloud-ops-lab-site-monitor`（Python 3.13 / arm64）を作成、上記コードを Deploy
- 環境変数3つを設定、一般設定でタイムアウトを **20秒**に
- 実行ロールに `sns:Publish` のインラインポリシーを追加

### Step 3. テスト（「テスト」タブで手動実行）
- **正常時**: `OK: http://13.196.53.206/ returned 200`（約0.4秒）→ 通知なし
- **異常時**: `SITE_URL` を一時的に `http://13.196.53.206:9/` に変更 → `URLError: timed out`（約10秒）→ `sns.publish` 実行
- 確認後 `SITE_URL` を元に戻す

### Step 4. EventBridge で自動化
- Lambdaに「トリガーを追加」→ EventBridge 新規ルール `cloud-ops-lab-site-monitor-5min` / スケジュール式 `rate(5 minutes)`
- EC2を停止した状態で 12:20 / 12:25 / 12:30 とアラートメールが届き、**5分間隔の自走を確認**

---

## つまずき & 学び

| 分類 | ポイント |
|---|---|
| SNS | **購読が削除されていても `publish` は成功する** — メッセージはトピックに届くが配信先が無いだけ。ID列が `削除済み` だった。「送れているのに来ない」ときは、まず購読の存在・ステータスを疑う。作り直して再確認で解決。 |
| SNS | **確認メールの「Confirm subscription」必須** — クリックするまで PendingConfirmation で届かない。SNSメールはGmailの迷惑メール/プロモーションに振り分けられやすい。 |
| Lambda | **タイムアウトはHTTP待ち時間より長く** — Lambda標準3秒だと `TIMEOUT=10` を待ち切れず誤検知する。20秒に延長。閉じたポートは10秒待ち切って失敗する（正常時は0.4秒）。 |
| Lambda | **boto3 は標準搭載** — `urllib`+`boto3` だけで書けばパッケージング作業ゼロ。 |
| 権限 | 実行ロールは初期状態でログ出力のみ。**`sns:Publish` を明示的に足す**必要がある(足りなければ実行時に AccessDenied)。 |
| 運用 | **EC2停止＝正常な異常検知** → 5分ごとにメール洪水。意図的に止める前に **EventBridgeルールを無効化**、起動後に有効化する運用が要る。 |
| コスト | この間隔なら Lambda / EventBridge / SNS いずれも無料枠内。RDSと違い付けっぱなしでも実質無課金。 |

---

## 完成後の運用メモ

- **一時的にサイトを止めるとき**: EventBridgeルール `cloud-ops-lab-site-monitor-5min` を無効化 → 起動後に有効化
- **演習を完全に終えるとき**: EventBridgeルール / Lambda / SNSトピック を削除すればクリーン
- 監視先URLや間隔の変更は、環境変数 `SITE_URL` とルールの `rate(...)` を書き換えるだけ

---

## 次へ

Phase 4-2完了。ロードマップ上の次は Phase 5（Docker）、Phase 6（Kubernetes）。Phase 3（GitHub + Terraform）の `.tf` 記述も未着手のまま残っている（更地から新規・ネットワーク層から `plan→apply→destroy` の方針で開始予定）。

---

*Cloud Ops Lab · Phase 4-2 実習ログ · ap-northeast-1 · 個人学習記録*
