# Phase 11: Tracing — AWS X-Ray の活用

## 概要

Phase 11 では AWS X-Ray を活用し、Lambda（site-monitor）の分散トレーシングを実装した。
Phase 9（Prometheus/Grafana）・Phase 10（CloudWatch Logs）と合わせ、
observability の三本柱である **メトリクス・ログ・トレーシング** がすべて揃った。

## 構成図

```
EventBridge (定期実行)
  └── Lambda: site-monitor
        ├── X-Ray Trace
        │     ├── Segment: Lambda Context
        │     └── Segment: Lambda Function
        │           ├── Subsegment: urllib (HTTP → WordPress EC2)
        │           └── Subsegment: SNS Publish (アラート送信)
        └── CloudWatch Logs (Phase 10)
```

## 実装内容

### 1. Lambda に X-Ray を有効化（Terraform）

`tracing_config` を `PassThrough` から `Active` に変更。

```hcl
resource "aws_lambda_function" "site_monitor" {
  # ...
  tracing_config {
    mode = "Active"
  }
}
```

### 2. IAM 権限追加（Terraform）

Lambda の実行ロールに X-Ray へのデータ送信権限を追加。

```hcl
{
  Effect = "Allow"
  Action = [
    "xray:PutTraceSegments",
    "xray:PutTelemetryRecords"
  ]
  Resource = "*"
}
```

### 3. X-Ray SDK をコードに組み込み

`aws-xray-sdk` を `pip install -t .` でLambdaディレクトリに展開し、zipに含める。
`patch_all()` により boto3・urllib の呼び出しが自動的にトレース対象となる。

```python
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

patch_all()
```

### 4. パッケージング設定変更（Terraform）

1ファイルzip から ディレクトリごとzip に変更し、SDKを含めてデプロイ。

```hcl
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/site_monitor.zip"
  excludes    = ["site_monitor.zip", "__pycache__"]
}
```

## Terraform 管理リソース一覧

| リソース | 内容 |
|---|---|
| `aws_lambda_function.site_monitor` | X-Ray Active モード有効化 |
| `aws_iam_role_policy.lambda_policy` | X-Ray 送信権限追加 |
| `data.archive_file.lambda_zip` | SDK込みディレクトリzip |

## 動作確認

- `aws lambda invoke` で手動実行
- CloudWatch → トレース画面でトレース (4件) を確認
- Trace Map で `クライアント → Lambda Context → Lambda Function` の流れを可視化
- セグメントのタイムライン：
  - `site-monitor`: 40ミリ秒
  - `Dwell Time`: 111ミリ秒（Lambda初期化待ち）
  - `Attempt #1`: 147ミリ秒（HTTPリクエスト）

## ハマりポイント

### Mac向けバイナリ問題
`pip install aws-xray-sdk -t .` をそのまま実行すると、
`wrapt` が Mac（x86_64）向けバイナリでインストールされ、Lambda（Linux）で動作しない。
`--platform manylinux2014_x86_64 --only-binary=:all:` オプションで Linux向けを明示的に指定する必要がある。

```bash
python3 -m pip install aws-xray-sdk \
  --target . \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all:
```

### SDKファイルの Git 管理
`pip install -t .` で展開されたSDKファイルはGit管理対象外とする。
`lambda/.gitignore` に各パッケージディレクトリを列挙して除外。

## Key Learnings

- **X-Ray の三概念**: Trace（1リクエスト全体）/ Segment（サービス単位）/ Subsegment（処理単位）
- **patch_all()**: boto3・urllib・requestsなど主要ライブラリを一括でトレース対象にする
- **X-Ray の本領**: 単一Lambdaでは恩恵が小さく、API Gateway → Lambda → DynamoDB のような多段構成で真価を発揮する
- **Observability の三本柱**: メトリクス（Prometheus/CloudWatch）・ログ（CloudWatch Logs）・トレーシング（X-Ray）がすべて揃った

## Observability スタック全体像

| レイヤー | ツール | Phase |
|---|---|---|
| メトリクス | Prometheus + Grafana | Phase 9 |
| メトリクス (AWS) | CloudWatch Alarm | Phase 6, 10 |
| ログ | CloudWatch Logs + Agent | Phase 10 |
| トレーシング | AWS X-Ray | Phase 11 |
