#!/bin/bash

# -------------------------
# INSTALL ARGOCD
# -------------------------

echo "Installing ArgoCD CLI..."
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/v2.6.0/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Install ArgoCD server on Kubernetes (EKS)
echo "Installing ArgoCD on EKS..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# -------------------------
# CONFIRM INSTALLATION
# -------------------------

echo "Installation complete! Verifying installations..."

# Check Prometheus service
sudo systemctl status prometheus --no-pager

# Check Grafana service
sudo systemctl status grafana-server --no-pager

# Check ArgoCD CLI version
argocd version --client
# -------------------------
# INSTALL PROMETHEUS
# -------------------------

echo "Installing Prometheus..."
PROMETHEUS_VERSION="2.45.0"
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus/
rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*

# Create a Prometheus user
sudo useradd --no-create-home --shell /bin/false prometheus || true
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Create Prometheus service
cat <<EOF | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
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

[Install]
WantedBy=multi-user.target
EOF

# Create default Prometheus config
cat <<EOF | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'jenkins'
    metrics_path: '/prometheus'
    static_configs:
      - targets: ['localhost:8080']
      
  - job_name: 'sonarqube'
    scrape_interval: 10s
    metrics_path: '/api/monitoring/metrics'
    static_configs:
      - targets: ['localhost:9000']
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Enable and start Prometheus
sudo systemctl enable prometheus
sudo systemctl start prometheus
## kubectl installtion
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
# -------------------------
# INSTALL GRAFANA
# -------------------------

echo "Installing Grafana..."
sudo apt-get install -y software-properties-common
sudo wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "All services (Prometheus, Grafana, ArgoCD) are installed and running!"
