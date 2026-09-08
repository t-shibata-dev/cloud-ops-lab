# Phase 9: Observability — Prometheus + Grafana

## 概要

Phase 6で構築した死活監視（Lambda + SNS）を発展させ、実務で求められるObservabilityの基盤を構築した。
監視対象サーバーのメトリクスをPrometheusで収集し、Grafanaで可視化するスタックを実装した。

---

## 構成図

```
WordPress EC2 (i-0c5818f0ef2518d19)     monitoring EC2 (i-0936d3a5a6d7fb60e)
┌─────────────────────────────┐         ┌──────────────────────────────────┐
│ Node Exporter :9100         │◄scrape──│ Prometheus :9090                 │
│ CPU / Mem / Disk / Net      │         │ scrape_interval: 15s             │
└─────────────────────────────┘         │                                  │
                                        │ Grafana :3000                    │
monitoring EC2自身                      │ Node Exporter Full Dashboard     │
┌─────────────────────────────┐         │ (Grafana ID: 1860)               │
│ Node Exporter :9100         │◄scrape──│                                  │
└─────────────────────────────┘         └──────────────────────────────────┘
```

---

## 使用リソース

| リソース | 詳細 |
|---|---|
| monitoring EC2 | `i-0936d3a5a6d7fb60e`, t3.small, ap-northeast-1 |
| Public IP | `35.77.91.184` |
| Prometheus | v2.53.0, `:9090` |
| Node Exporter | v1.8.1, `:9100` |
| Grafana | v13.2.1, `:3000` |
| Terraform state | `s3://cloud-ops-lab-tfstate/phase9-observability/terraform.tfstate` |

---

## ディレクトリ構成

```
terraform/phase9-observability/
├── main.tf           # EC2, Security Group, data source (VPC/Subnet)
├── variables.tf      # region, project_name, ami_id, instance_type
├── outputs.tf        # monitoring_public_ip, grafana_url, prometheus_url
└── user_data.sh      # Prometheus, Node Exporter, Grafana 自動インストール
```

---

## セットアップ手順

### 1. Terraform でmonitoring EC2を起動

```hcl
# main.tf 抜粋
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["cloud-ops-lab-vpc"]
  }
}

data "aws_subnet" "public" {
  filter {
    name   = "tag:Name"
    values = ["cloud-ops-lab-public-1a"]  # 実際のタグ名を確認して指定
  }
}

resource "aws_instance" "monitoring" {
  ami                    = var.ami_id
  instance_type          = "t3.small"    # t3.microはメモリ不足でフリーズ
  iam_instance_profile   = "cloud-ops-lab-ec2-ssm-role"
  user_data              = file("${path.module}/user_data.sh")
}
```

```bash
cd terraform/phase9-observability
terraform init
terraform apply
```

### 2. WordPress EC2にNode Exporterをインストール

```bash
# SSM経由で接続
aws ssm start-session --target i-0c5818f0ef2518d19 --region ap-northeast-1

# Node Exporterインストール
NODE_VERSION="1.8.1"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.linux-amd64.tar.gz \
  -O /tmp/node_exporter.tar.gz
tar xf /tmp/node_exporter.tar.gz -C /tmp/
sudo cp /tmp/node_exporter-${NODE_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter

sudo tee /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

### 3. WordPress EC2のSecurity Groupに9100番ポートを追加

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-03c44ef5df323fd75 \
  --protocol tcp \
  --port 9100 \
  --cidr 10.0.1.0/24 \
  --region ap-northeast-1
```

### 4. PrometheusにWordPress EC2をscrapeターゲットとして追加

```bash
# monitoring EC2にSSM接続後
sudo tee /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'monitoring_node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'wordpress_node'
    static_configs:
      - targets: ['10.0.1.25:9100']
EOF

sudo systemctl restart prometheus
```

### 5. GrafanaにPrometheusデータソースを追加

1. `http://35.77.91.184:3000` → admin/admin でログイン
2. Connections → Data sources → Add data source → Prometheus
3. URL: `http://localhost:9090`
4. Save & test → "Successfully queried the Prometheus API"

### 6. Node Exporter Fullダッシュボードをインポート

1. Dashboards → New → Import
2. ID `1860` を入力 → Load
3. Import

---

## 確認したメトリクス（WordPress EC2）

| メトリクス | 値 |
|---|---|
| CPU Busy | 66.6% |
| RAM Used | 43.7% |
| Root FS Used | 83.5% ⚠️ |
| SWAP Used | 11.5% |
| Uptime | 1.2 days |

---

## トラブルシューティング

### Grafana GPGキーエラー

**症状**: `NO_PUBKEY 963FA27710458545` でGrafanaインストール失敗

**原因**: `user_data.sh`で古い形式のキー取得方法を使用していた

**解決策**:
```bash
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | sudo tee /etc/apt/sources.list.d/grafana.list
```

### t3.microでサービスフリーズ

**症状**: `systemctl enable --now prometheus node_exporter grafana-server` でSSMセッションごとフリーズ

**原因**: Grafana（~600MB）+ Prometheus + Node Exporterがt3.microの1GBメモリを超過

**解決策**: t3.small（2GB）に変更。`terraform apply -replace="aws_instance.monitoring"`で再作成

### wordpress_node DOWN（context deadline exceeded）

**症状**: PrometheusターゲットでWordPress EC2がDOWN

**原因**: WordPress EC2のSecurity Groupが9100番ポートのingressを許可していなかった

**解決策**: `aws ec2 authorize-security-group-ingress` で`10.0.1.0/24`からの9100番を許可

### data "aws_subnet" でno matching found

**症状**: `terraform plan`で`no matching EC2 Subnet found`エラー

**原因**: phase4のvpc.tfでは`${var.project_name}-public-subnet`というタグ名を定義していたが、
実際のAWSリソースには`cloud-ops-lab-public-1a`というタグが付いていた（手動作成時に差異が生じていた）

**解決策**: `aws ec2 describe-subnets`で実際のタグ名を確認してfilterを修正

---

## 既知の課題・今後の対応

| 課題 | 内容 |
|---|---|
| WordPress EC2のNode Exporter | Terraformで管理されていない（手動インストール）|
| SG 9100番ポート | Terraformで管理されていない（手動追加）|
| Root FS 83.5% | WordPress EC2のディスク使用率が高い。不要ファイルの削除またはEBSの拡張を検討 |
| Prometheusの永続化 | EC2再起動後にメトリクス履歴が消える。EBSをマウントして永続化するか要検討 |

---

## Key Learnings

**CloudWatch AgentよりPrometheusを選ぶ理由**
CloudWatch AgentはAWS専用。PrometheusはGCP・Azure・オンプレでも同じ構成で動く業界標準。
SREとしてマルチクラウド・クラウド横断のスキルを示すにはPrometheus + Grafanaが有効。

**data sourceでタグ検索する際は実際のリソースを確認する**
Terraformコードのタグ定義と実際にAWSに付いているタグが一致しない場合がある。
特にPhase 3以前に手動で作成したリソースは要注意。`aws ec2 describe-*`で必ず確認する。

**t3.microはPrometheus + Grafanaには不足**
Grafana単体で約600MBのメモリを消費する。Node Exporterとprometheusを加えるとt3.microの1GBでは不足。
監視スタックにはt3.small（2GB）以上を使う。

**Security Groupはサービスごとに考える**
Node Exporterの9100番ポートはPrometheusサーバーのIPからのみ許可するのが原則。
今回はサブネット全体（`10.0.1.0/24`）で許可したが、本番ではSecurity Group間の参照（`source_security_group_id`）を使うべき。

**systemctlコマンドはSSMセッション内で固まることがある**
`systemctl status`はデフォルトでページャーを起動するため、SSMセッションで固まる。
必ず`--no-pager`オプションを付ける。また`enable --now`で複数サービスを一度に起動するより1つずつ起動するほうが安全。

---

## SREとしての文脈

**Observabilityの3本柱との対応**

| 柱 | 今回の実装 | 備考 |
|---|---|---|
| Metrics | Prometheus + Grafana ✅ | 本Phaseで実装 |
| Logs | 未実装 | CloudWatch Logsで対応予定 |
| Traces | 未実装 | AWS X-Rayで対応予定 |

Phase 6の死活監視（アラート）に加え、**何が起きているかを継続的に可視化する**基盤を構築した。
これにより「サイトが落ちた」だけでなく「落ちる前にディスクが逼迫していた」「CPUスパイクが先行していた」という
事後分析（Post-mortem）が可能になる。

実務では監視対象が数十〜数百台になるため、PrometheusのService DiscoveryやAnsibleによる
Node Exporterの一括デプロイが必要になるが、本Phaseで基本原理を確認した。
