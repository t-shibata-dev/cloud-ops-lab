# Phase 3: GitHub + Terraform

## やったこと

### GitHub整備
- .gitignoreを作成（*.tfvars, .terraform/, tfstate系を除外）
- terraform/ディレクトリを追加してpush

### Terraformで構築したリソース
- vpc.tf: VPC・パブリックサブネット・IGW・ルートテーブル
- security_groups.tf: EC2用SG（80/443）・RDS用SG（3306、EC2 SGから参照）
- ec2.tf: EC2・EIP・IAMロール（SSM+S3）
- s3.tf: S3バケット（パブリックアクセスブロック・バージョニング）
- rds.tf: RDS MySQL 8.0・プライベートサブネット2AZ・SubnetGroup

### 学んだこと
- plan → apply → destroyのサイクル
- (known after apply)の意味（依存関係の解決）
- sensitive = trueでパスワードを保護
- terraform.tfvarsはgitignoreで除外する運用

## トラブルと解決
- IAM権限不足 → cloud-ops-cliにFullAccessポリシーを追加
- DBSubnetGroupAlreadyExists → 手動作成済みのSubnetGroupを削除
