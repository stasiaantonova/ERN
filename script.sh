#!/bin/bash
read -p "Enter NODE name:" NODE
echo 'export NODE='$NODE
read -p "Enter IP server :" IP
echo 'export IP='$IP
read -p "TOKEN telegrambot:" TOKEN
echo 'export TOKEN='$TOKEN

cd $HOME && \
wget https://github.com/prometheus/node_exporter/releases/download/v1.2.0/node_exporter-1.2.0.linux-amd64.tar.gz && \
tar xvf node_exporter-1.2.0.linux-amd64.tar.gz && \
rm node_exporter-1.2.0.linux-amd64.tar.gz && \
sudo mv node_exporter-1.2.0.linux-amd64 node_exporter && \
chmod +x $HOME/node_exporter/node_exporter && \
mv $HOME/node_exporter/node_exporter /usr/bin && \
rm -Rvf $HOME/node_exporter/

sudo tee /etc/systemd/system/exporterd.service > /dev/null <<EOF
[Unit]
Description=node_exporter
After=network-online.target
[Service]
User=$USER
ExecStart=/usr/bin/node_exporter
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload && \
sudo systemctl enable exporterd && \
sudo systemctl restart exporterd
wget $(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest |grep "tag_name" | awk '{print "https://github.com/prometheus/prometheus/releases/download/" substr($2, 2, length($2)-3) "/prometheus-" substr($2, 3, length($2)-4) ".linux-amd64.tar.gz"}')

tar xvf prometheus-*.tar.gz
sudo cp ./prometheus-*.linux-amd64/prometheus /usr/local/bin/
sudo cp ./prometheus-*.linux-amd64/promtool /usr/local/bin/ 
sudo cp -r ./prometheus-*.linux-amd64/consoles /etc/prometheus
sudo cp -r ./prometheus-*.linux-amd64/console_libraries /etc/prometheus

sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus
sudo mkdir /var/lib/prometheus

sudo chown -R prometheus:prometheus /etc/prometheus/ /var/lib/prometheus/

rm -rf ./prometheus*

mv /etc/prometheus/prometheus.yml
sudo tee ~/etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
rule_files:
  - 'rules.yml'
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - $IP:9093
scrape_configs:
  - job_name: "$NODE"
    scrape_interval: 5s
    static_configs:
      - targets: ["$IP:9090","$IP:9615"]
EOF

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
  Description=Prometheus Monitoring
  Wants=network-online.target
  After=network-online.target
[Service]
  User=prometheus
  Group=prometheus
  Type=simple
  ExecStart=/usr/local/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yml \
  --storage.tsdb.path /var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries
  --storage.tsdb.retention.time 30d \
  --web.enable-admin-api
  ExecReload=/bin/kill -HUP $MAINPID
[Install]
  WantedBy=multi-user.target
EOF

cd /etc/prometheus
sudo chown prometheus:prometheus rules.yml

sudo systemctl daemon-reload
sudo systemctl start prometheus.service
sudo systemctl enable prometheus.service

cd ~
wget https://github.com/prometheus/alertmanager/releases/download/v0.24.0/alertmanager-0.24.0.linux-amd64.tar.gz;
tar xvf alertmanager-0.24.0.linux-amd64.tar.gz
rm alertmanager-0.24.0.linux-amd64.tar.gz

mkdir /etc/alertmanager /var/lib/prometheus/alertmanager

cd alertmanager-0.24.0.linux-amd64

cp alertmanager amtool /usr/local/bin/ && cp alertmanager.yml /etc/alertmanager

useradd --no-create-home --shell /bin/false alertmanager

chown -R alertmanager:alertmanager /etc/alertmanager 
/var/lib/prometheus/alertmanager
chown alertmanager:alertmanager /usr/local/bin/{alertmanager,amtool}

sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<EOF
[Unit]
Description=AlertManager Server Service
Wants=network-online.target
After=network-online.target
[Service]
User=root
Group=root
Type=simple
ExecStart=/usr/local/bin/alertmanager --config.file /etc/alertmanager/alertmanager.yml --web.external-url=http://$IP_server:9093 --cluster.advertise-address='0.0.0.0:9093'
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<EOF
route:
  group_by: ['alertname', 'instance', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'telepush'
receivers:
  - name: 'telepush'
    webhook_configs:
      - url: 'https://telepush.dev/api/inlets/alertmanager/"$TOKEN"'
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF

sudo tee /etc/prometheus/rules.yml > /dev/null <<EOF
groups:
  - name: alert_rules
    rules:
      - alert: $NODE
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "$NODE"
          description: "Node has been down for more than 1 minute."          
EOF

sudo systemctl daemon-reload && sudo systemctl enable alertmanager && sudo systemctl start alertmanager && sudo systemctl status alertmanager

sudo systemctl restart prometheus.service
sudo systemctl restart alertmanager
