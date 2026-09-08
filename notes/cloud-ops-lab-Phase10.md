# Phase 10: Logs — CloudWatch Logs の活用

## 概要

Phase 10 では AWS CloudWatch Logs を活用し、EC2（WordPress/Apache）のログを
クラウドネイティブな方法で収集・監視・分析する仕組みを構築した。
Phase 6（Lambda監視）・Phase 9（Prometheus/Grafana）と連携し、
Observability スタックの「ログ」レイヤーを完成させた。

## 構成図

```
EC2 (WordPress)
└── CloudWatch Agent
      ├── /var/log/apache2/access.log
      │     └── Log Group: /cloud-ops-lab/ec2/apache/access (30日保持)
      └── /var/log/apache2/error.log
            └── Log Group: /cloud-ops-lab/ec2/apache/error (30日保持)
                  └── Metric Filter: ApacheErrorCount
                        └── CloudWatch Alarm: ApacheErrorAlert
                              └── SNS: cloud-ops-lab-site-alert
                                    └── メール通知
```

## 実装内容

### Step 1: CloudWatch Agent のインストール

Ubuntu の標準リポジトリには含まれないため、AWS の公式 deb パッケージを直接取得してインストール。

```bash
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb
```

バージョン: `1.300072.0b1766`

### Step 2: IAM ロールへのポリシー追加

既存の `cloud-ops-lab-ec2-ssm-role` に `CloudWatchAgentServerPolicy` を追加。

### Step 3: エージェント設定ファイルの作成

`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` を作成し、
Apache のアクセスログとエラーログを収集対象に設定。

- Log Stream 名: `{instance_id}`（EC2 インスタンス ID で識別）
- flush interval: 15 秒

### Step 4: Log Group の保持期間設定

| Log Group                            | 保持期間 |
| ------------------------------------ | -------- |
| `/cloud-ops-lab/ec2/apache/access`   | 30 日    |
| `/cloud-ops-lab/ec2/apache/error`    | 30 日    |

### Step 5: メトリクスフィルター & アラーム

- フィルターパターン: `[severity="*error*", ...]`
- メトリクス: `CloudOpsLab/Apache / ApacheErrorCount`
- アラーム: 5 分間で 1 件以上のエラーで ALARM → SNS 通知

### Step 6: Logs Insights によるアクセス分析

User-Agent 別リクエスト数を集計（直近 1 時間、989 件）：

| User-Agent                    | リクエスト数 | 分類                       |
| ----------------------------- | -----------: | -------------------------- |
| Mozilla/5.0 (Windows NT...)   |          809 | ブラウザ偽装ボット（疑い） |
| SiteMonitor/1.0               |           74 | Phase 6 Lambda 監視        |
| Python-urllib/3.14            |           74 | Phase 6 Lambda 監視        |
| WordPress/7.1                 |            6 | WordPress 内部通信         |
| CensysInspect/1.1             |            4 | インターネットスキャナー   |
| zgrab/0.x                     |            1 | セキュリティスキャナー     |

**SRE 観点**: 全トラフィックの約 82% がブラウザ偽装ボットと推定される。
CensysInspect・zgrab は外部からのポートスキャンであり、
WAF や Security Group による遮断を今後の課題とする。

## Terraform 管理範囲

| リソース                          | Terraform | 備考                               |
| --------------------------------- | :-------: | ---------------------------------- |
| CloudWatch Agent インストール     | ✗ 手動    | EC2 内部のため                     |
| Agent 設定ファイル                | ✗ 手動    | EC2 内部のため                     |
| IAM: CloudWatchAgentServerPolicy  | ✓         | `aws_iam_role_policy_attachment`   |
| Log Group: apache/access          | ✓         | 保持期間 30 日                     |
| Log Group: apache/error           | ✓         | 保持期間 30 日                     |
| メトリクスフィルター              | ✓         | `aws_cloudwatch_log_metric_filter` |
| CloudWatch アラーム               | ✓         | `aws_cloudwatch_metric_alarm`      |

既存リソースは `terraform import` で state に取り込み後、`terraform apply` で
タグ付け・設定を統一した。

## 技術的気づき

- **apt では install 不可**: CloudWatch Agent は Ubuntu 標準リポジトリに存在しない。
  AWS の S3 から deb を直接取得する必要がある。
- **terraform import の必要性**: 手動作成リソースを Terraform 管理下に置く際は、
  `terraform import` で既存リソースを state に取り込んでから apply する。
  そうしないと既存リソースとの衝突が発生する。
- **macOS の date コマンド**: Linux の `date -d` は macOS では動作しない。
  macOS では `date -v-1H` を使用する。

## 残課題

- CloudWatch Agent のインストール・設定を SSM ドキュメントまたは
  EC2 user_data で自動化する（現状は手動）
- Phase 9 の Node Exporter（WordPress EC2）の SG ルールを Terraform 管理に移行
- ボット・スキャナーに対する WAF または Security Group での遮断

## Observability スタックの現状

| レイヤー | ツール                  | 状態            |
| -------- | ----------------------- | --------------- |
| Metrics  | Prometheus + Grafana    | ✓ Phase 9 完了  |
| Logs     | CloudWatch Logs         | ✓ Phase 10 完了 |
| Traces   | AWS X-Ray               | 未実装          |
