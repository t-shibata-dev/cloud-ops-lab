# Phase 8：CI/CD（GitHub Actions + Terraform）

## 概要

GitHub Actions を使い、Terraform の plan/apply を自動化する CI/CD パイプラインを構築した。
main ブランチへの push で自動的に Terraform が実行される仕組みを実装した。

---

## 構成

```
コードを push (terraform/phase6-monitoring/**)
    ↓
GitHub Actions トリガー
    ↓
Checkout → AWS 認証 → Terraform Init
    ↓
Terraform Plan（差分確認）
    ↓
Terraform Apply（main ブランチへの push 時のみ）
```

---

## 実装したリソース・設定

| 項目 | 内容 |
|---|---|
| GitHub Actions ワークフロー | `.github/workflows/terraform.yml` |
| S3 バックエンド | `cloud-ops-lab-tfstate` (state 管理) |
| IAM OIDC Provider | `token.actions.githubusercontent.com` (作成済み・未使用) |
| IAM Role | `github-actions-terraform-role` (作成済み・未使用) |
| 認証方式 | IAM キー（GitHub Secrets） |
| GitHub Secrets | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `ALERT_EMAIL` |

---

## ワークフローの設計

### トリガー条件

```yaml
on:
  push:
    branches:
      - main
    paths:
      - 'terraform/phase6-monitoring/**'
  pull_request:
    branches:
      - main
    paths:
      - 'terraform/phase6-monitoring/**'
```

`paths` フィルターで対象ディレクトリ変更時のみ起動。
**注意：** ワークフローファイル自体の追加は `paths` 条件を満たさないため、
対象ディレクトリへのダミー変更で初回トリガーが必要。

### Apply の条件

```yaml
if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

main への push 時のみ apply。PR 時は plan のみ実行。

---

## Terraform S3 バックエンド

```hcl
backend "s3" {
  bucket = "cloud-ops-lab-tfstate"
  key    = "phase6-monitoring/terraform.tfstate"
  region = "ap-northeast-1"
}
```

`terraform init -migrate-state` でローカル state を S3 に移行した。

バケット用途の整理：

| バケット名 | 用途 |
|---|---|
| `cloud-ops-lab-media-2026` | Phase 1/2 WordPress 用 |
| `cloud-ops-lab-media-205382053604` | Phase 4 boto3 テスト用 |
| `cloud-ops-lab-tfstate` | Phase 8 Terraform state 専用 |

---

## OIDC 認証の試みと課題

当初 OIDC（キーレス認証）を試みたが、GitHub の新ランナーインフラへの移行により
トークン発行元ドメインが `token.actions.githubusercontent.com` ではなく
`run-actions-3-azure-eastus.actions.githubusercontent.com` になっており、
AWS の OIDC Provider との検証に失敗した。

```
Error: Could not assume role with OIDC:
The web identity token provided could not be validated.
```

OIDC Provider と IAM Role は作成済みのため、GitHub のインフラ移行完了後に
再度 OIDC 認証への切り替えが可能。

---

## トラブルシューティング

### paths フィルターでワークフローが起動しない

ワークフローファイル追加のコミット自体は `paths` フィルターを満たさない。
対処：`terraform/phase6-monitoring/main.tf` にダミー変更を加えて push。

### OIDC 認証エラー（未解決）

GitHub の新ランナーインフラ（Azure East US）からのトークン発行元ドメインが
AWS OIDC Provider に登録されたドメインと一致しないため認証失敗。
現時点では IAM キー方式で代替。

---

## 学習ポイント

- GitHub Actions の `paths` フィルターはワークフローファイル自体の変更では発火しない
- Terraform の state は S3 バックエンドに移行することで CI/CD 環境間で共有できる
- `terraform apply -auto-approve` は CI/CD 環境でのみ使用する
- OIDC 認証はキーレスで安全だが、クラウドプロバイダーとの連携仕様変更に影響を受ける
- IAM キー方式はシンプルだが、キーの定期ローテーションが必要
- GitHub Secrets に認証情報を登録することでコードに機密情報を含めずに済む

---

## コスト

| リソース | 費用 |
|---|---|
| GitHub Actions | 無料枠内（Public リポジトリは無制限） |
| S3 state バケット | ほぼ無料（state ファイルは数KB） |
| IAM OIDC Provider / Role | 無料 |
