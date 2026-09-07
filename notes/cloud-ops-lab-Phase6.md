# Phase 6：Lambda + SNS によるサイト監視

## 概要

AWS Lambda と SNS を使い、WordPress サイトの死活監視システムを Terraform で構築した。
EventBridge による定期実行で、サイトダウン時に自動でメール通知が届く仕組みを実装した。

---

## 構成図

```
EventBridge (rate: 5分ごと)
    ↓
Lambda Function (Python 3.12)
    ↓ HTTP GET
WordPress on EC2 (http://13.196.53.206/)
    ↓
    ├─ 200 OK → ログ記録のみ
    └─ タイムアウト / エラー → SNS Publish
                                    ↓
                              メール通知
```

---

## 作成リソース

| リソース | 名前 | 備考 |
|---|---|---|
| SNS Topic | `site-monitor-alert` | アラート送信先 |
| SNS Subscription | Email | 購読確認メール要クリック |
| IAM Role | `site-monitor-lambda-role` | Lambda 実行ロール |
| IAM Policy | `site-monitor-lambda-policy` | CloudWatch Logs + SNS Publish |
| Lambda Function | `site-monitor` | Python 3.12 / timeout 15秒 |
| EventBridge Rule | `site-monitor-schedule` | rate(5 minutes) |
| EventBridge Target | - | Lambda に紐付け |

---

## ディレクトリ構成

```
~/cloud-ops-lab/terraform/phase6-monitoring/
├── main.tf
├── variables.tf
├── outputs.tf
└── lambda/
    ├── site_monitor.py
    └── site_monitor.zip   # archive_file で自動生成
```

---

## Lambda コード概要（site_monitor.py）

- `urllib.request` で対象 URL に HTTP GET
- ステータス 200 → 正常ログ出力のみ
- タイムアウト / 非200 → SNS に Publish してメール送信
- 環境変数で `TARGET_URL` / `SNS_TOPIC_ARN` / `TIMEOUT_SECONDS` を管理

---

## Terraform 実装のポイント

### Lambda ZIP の自動生成

```hcl
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/site_monitor.py"
  output_path = "${path.module}/lambda/site_monitor.zip"
}
```

`source_code_hash` を指定することでコード変更時に自動デプロイされる。

### EventBridge → Lambda の権限

```hcl
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.site_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
```

EventBridge が Lambda を invoke するには明示的な許可が必要。

### IAM 権限（cloud-ops-cli ユーザーに追加）

| ポリシー | 用途 |
|---|---|
| `AmazonSNSFullAccess` | SNS Topic 作成・Publish |
| `CloudWatchEventsFullAccess` | EventBridge ルール作成 |
| `AWSLambda_FullAccess` | Lambda 関数作成 |

---

## 動作確認結果

### 正常系（EC2 起動中）

```json
{
  "status": "ok",
  "code": 200
}
```

ログ：`OK: http://13.196.53.206/ returned 200`
所要時間：127ms

### 異常系（EC2 停止中）

```json
{
  "status": "alert_sent",
  "error": "<urlopen error timed out>"
}
```

メール件名：`[SiteMonitor] Site Down Alert`  
メール本文：`[ALERT] Site down: http://13.196.53.206/ Error: <urlopen error timed out>`

→ アラートメール受信を確認済み ✅

---

## トラブルシューティング

### SNS Subscription Confirmed の操作ミス

`apply` 後に届くメールに確認リンクと解除リンクが両方含まれている。  
解除リンクをクリックしてしまうと `Subscription removed` になる。  
対処：`terraform apply` を再実行して Subscription を再作成し、確認メールの **"Confirm subscription"** をクリック。

---

## 学習ポイント

- Lambda は ZIP 形式でデプロイする。`archive_file` data source で Terraform から自動生成できる
- SNS のメール購読は作成後に**受信者側での確認操作が必要**（Terraform だけでは完結しない）
- EventBridge → Lambda の invoke には `aws_lambda_permission` が必要（SNS や S3 との違い）
- Lambda の環境変数で設定値を外部化することで、コードを変えずに監視対象を切り替えられる
- Phase 4 で作成した `ec2_control.py` を使って EC2 の停止・起動操作を CLI から実施した

---

## コスト

| リソース | 無料枠 | 備考 |
|---|---|---|
| Lambda | 月100万リクエスト無料 | 5分ごと = 月約8,640回 → 無料枠内 |
| SNS | 月100万回 Publish 無料 | アラート発火時のみ課金対象 |
| EventBridge | 月100万イベント無料 | 無料枠内 |
| CloudWatch Logs | 5GB/月無料 | ログ量次第 |

→ 通常運用では**ほぼ無料**で稼働する。
