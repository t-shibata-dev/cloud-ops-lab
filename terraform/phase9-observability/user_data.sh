#!/bin/bash
set -e

# ── システム更新 ──────────────────────────────────────
apt-get update -y
apt-get install -y wget curl

# ── Prometheus ────────────────────────────────────────
PROM_VERSION="2.53.0"
useradd --no-create-home --shell /bin/false prometheus

wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz \
  -O /tmp/prometheus.tar.gz
tar xf /tmp/prometheus.tar.gz -C /tmp/
cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/promtool  /usr/local/bin/

mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'monitoring_node'
    static_configs:
      - targets: ['localhost:9100']
EOF

cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ── Node Exporter（監視サーバー自身のメトリクス）────────
NODE_VERSION="1.8.1"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.linux-amd64.tar.gz \
  -O /tmp/node_exporter.tar.gz
tar xf /tmp/node_exporter.tar.gz -C /tmp/
cp /tmp/node_exporter-${NODE_VERSION}.linux-amd64/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter

cat > /etc/systemd/system/node_exporter.service <<'EOF'
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

# ── Grafana ───────────────────────────────────────────
apt-get install -y apt-transport-https software-properties-common
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list
apt-get update -y
apt-get install -y grafana

# ── 全サービス起動 ────────────────────────────────────
systemctl daemon-reload
systemctl enable prometheus node_exporter grafana-server
systemctl start  prometheus node_exporter grafana-server
