# cloud-ops-lab

AWS 上の WordPress サイトを題材に、インフラを **手動構築 → コード化 → 自動化 → コンテナ化 → 可観測性** まで段階的に積み上げた、SRE 学習用のポートフォリオです。

- **位置づけ**: 学習用ラボ環境（本番運用サイトではありません）
- **リージョン**: `ap-northeast-1`（東京）
- **方針**: マネージドサービスに頼り切る前に、コンソール操作でネットワーク・サーバー・権限・運用の挙動を理解し、その後 Terraform でコード化する

> 課金源となるリソース（RDS 等）は検証後に停止・削除しているため、リポジトリ内の構成がそのまま常時稼働しているわけではありません。

---

## 設計方針

- **SSH(22) を開けず SSM Session Manager で運用** — 攻撃面を減らし、接続元 IP が変わっても運用できる
- **アクセスキーをサーバーに置かず IAM ロールで権限委譲** — 最小権限を意識
- **手動で理解してからコード化** — Terraform で抽象化する前に実機で挙動を掴む
- **学習後は課金源を停止・削除** — RDS 等は検証後にクリーンアップ

---

## 技術スタック

| レイヤー       | 使用技術 |
|----------------|----------|
| ネットワーク   | VPC / サブネット / IGW / ルートテーブル / セキュリティグループ |
| コンピュート   | EC2（t3.micro / t3.small）, Ubuntu Server 26.04 LTS |
| Web / App      | Apache 2.4, PHP 8.5, WordPress |
| データベース   | MySQL 8.4（EC2 同居 → RDS `db.t4g.micro` へ移行検証） |
| ストレージ     | S3（画像オフロード / Terraform state） |
| サーバーレス   | Lambda（Python）, SNS, EventBridge |
| IaC            | Terraform（S3 バックエンド） |
| コンテナ       | Docker, Docker Compose, Kubernetes（Colima / k3s） |
| CI/CD          | GitHub Actions |
| 可観測性       | Prometheus, Grafana, Node Exporter, CloudWatch Logs, AWS X-Ray |
| 権限・運用     | IAM（ロール / 最小権限）, Systems Manager（Session Manager） |

---

## ロードマップ（全 11 フェーズ・完了）

| Phase | テーマ                          | 状態        |
|-------|---------------------------------|-------------|
| 1     | EC2 + S3 で WordPress 手動構築   | 完了        |
| 2     | RDS 分離（三層アーキテクチャ）    | 完了・撤去  |
| 3     | GitHub + Terraform 導入          | 完了        |
| 4     | Lambda 死活監視（Python）        | 完了        |
| 5     | Docker / コンテナ                | 完了        |
| 6     | 死活監視の Terraform 化          | 完了        |
| 7     | Kubernetes 基礎                  | 完了        |
| 8     | CI/CD（GitHub Actions）          | 完了        |
| 9     | 可観測性: Metrics                | 完了        |
| 10    | 可観測性: Logs                   | 完了        |
| 11    | 可観測性: Traces                 | 完了        |

可観測性の三本柱（**メトリクス** / **ログ** / **トレーシング**）を Phase 9–11 で実装しています。

各フェーズの詳細な作業記録・つまずき・学びは [`notes/`](./notes/) に、全体の技術サマリは [`notes/cloud-ops-lab-summary.org`](./notes/cloud-ops-lab-summary.org) にまとめています。

---

## ディレクトリ構成

```
.
├── .github/workflows/
│   └── terraform.yml            # GitHub Actions（Terraform の plan/apply）
├── docker/
│   └── compose.yaml             # WordPress + MySQL のコンテナ定義（arm64）
├── k8s/
│   └── nginx/                   # Deployment / Service（k3s での基礎検証）
├── scripts/                     # boto3 による運用スクリプト
│   ├── ec2_control.py           # EC2 の状態確認・起動/停止
│   ├── rds_snapshot.py          # RDS スナップショット取得
│   └── upload_to_s3.py          # S3 へのファイルアップロード
├── terraform/
│   ├── phase4/                  # VPC / サブネット / SG / EC2 / RDS の基盤 IaC
│   ├── phase6-monitoring/       # Lambda + SNS + EventBridge 死活監視
│   ├── phase9-observability/    # 監視用 EC2（Prometheus/Grafana）+ user_data
│   └── phase10-logs/            # CloudWatch Logs / メトリクスフィルタ / アラーム
├── notes/                       # 各フェーズの作業ノート（Markdown / Org）
└── overview/                    # プロジェクト概要スライド（Org → HTML）
```

> **注記**: `terraform/` 配下のサブディレクトリ名の連番（`phase4`, `phase6-monitoring` …）は、上記ロードマップの Phase 番号と一致していません。作成順の都合による命名です。各ディレクトリの内容は上記コメントを参照してください。

---

## Terraform

- state は S3 バックエンド（バケット `cloud-ops-lab-tfstate`）で管理し、ディレクトリごとに state key を分離しています。
- 手動作成済みのリソースは `terraform import` で取り込んでから `apply` する運用（実機で理解 → コード化の方針に沿う）。

各ディレクトリでの基本操作:

```bash
cd terraform/phase4        # 対象ディレクトリへ
terraform init
terraform plan
terraform apply
```

> `*.tfvars` / `.terraform/` / `terraform.tfstate*` などは [`.gitignore`](./.gitignore) で除外しています。認証情報や機密変数はコミットしません。

---

## CI/CD

[`.github/workflows/terraform.yml`](./.github/workflows/terraform.yml) が GitHub Actions のパイプラインです。

- 対象: `terraform/phase6-monitoring/**` の変更（`paths` フィルタで限定）
- `push` / `pull_request`（main）で `terraform plan`、main への `push` 時のみ `terraform apply -auto-approve`
- 認証: **IAM アクセスキー方式**（GitHub Secrets: `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `ALERT_EMAIL`）
  - OIDC を試みたが、GitHub ランナー側のトークン発行ドメインが想定と異なり失敗したため、IAM キー方式にフォールバックしている

---

## コンテナ / Kubernetes

- [`docker/compose.yaml`](./docker/compose.yaml): `wordpress:latest` + `mysql:8.0` を Apple Silicon 向け（`linux/arm64`）で起動。WordPress は `localhost:8080` で公開。
- [`k8s/nginx/`](./k8s/nginx/): Colima 内蔵 k3s 上での Deployment / Service の基礎検証。
  - NodePort は Mac から直接アクセスできないため、`kubectl port-forward` で到達する。

---

## 既知の技術的負債（今後の課題）

- CloudWatch Agent のインストールが SSM / `user_data` で自動化されていない
- Phase 9 の Node Exporter 用 SG ルール（ポート 9100）が Terraform 管理外
- 検出済みのボット / スキャナ（CensysInspect, zgrab 等）に対する WAF / SG ブロックが未設定
- WordPress EC2 のルートファイルシステム使用率が高め（Phase 9 時点で約 83%）

---

## ライセンス / 免責

学習・ポートフォリオ目的のリポジトリです。掲載しているリソース ID・設定値は当時の検証環境のものであり、恒久稼働を保証するものではありません。
