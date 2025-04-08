#!/bin/bash

# === PART 1: Install all required tools and services ===

# Update system packages
echo "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install common dependencies
echo "Installing common dependencies..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    unzip \
    git

# Install Docker
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $(whoami)

# Install Docker Compose
echo "Installing Docker Compose..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Java
echo "Installing Java..."
sudo apt-get install -y openjdk-17-jdk

# Install Jenkins
echo "Installing Jenkins..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Install Terraform
echo "Installing Terraform..."
TERRAFORM_VERSION="1.5.7"
wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Install SonarQube Scanner CLI
echo "Installing SonarQube Scanner..."
SONAR_SCANNER_VERSION="4.8.0.2856"
wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip
unzip sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip
sudo mv sonar-scanner-${SONAR_SCANNER_VERSION}-linux /opt/sonar-scanner
echo 'export PATH=$PATH:/opt/sonar-scanner/bin' | sudo tee -a /etc/profile.d/sonar-scanner.sh
source /etc/profile.d/sonar-scanner.sh
rm sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip

# Install SonarQube Server using Docker (easier to maintain)
echo "Installing SonarQube Server using Docker..."
# Create necessary directories
sudo mkdir -p /opt/sonarqube/data
sudo mkdir -p /opt/sonarqube/logs
sudo mkdir -p /opt/sonarqube/extensions

# Set permissions for SonarQube directories
sudo chown -R 1000:1000 /opt/sonarqube

# Create docker-compose.yml for SonarQube
cat <<EOF | sudo tee /opt/sonarqube/docker-compose.yml
version: '3'
services:
  sonarqube:
    image: sonarqube:latest
    container_name: sonarqube
    ports:
      - "9000:9000"
    networks:
      - sonarnet
    environment:
      - SONAR_JDBC_URL=jdbc:postgresql://sonarqube-db:5432/sonar
      - SONAR_JDBC_USERNAME=sonar
      - SONAR_JDBC_PASSWORD=sonar
    volumes:
      - /opt/sonarqube/data:/opt/sonarqube/data
      - /opt/sonarqube/logs:/opt/sonarqube/logs
      - /opt/sonarqube/extensions:/opt/sonarqube/extensions
    restart: always
    depends_on:
      - sonarqube-db
  
  sonarqube-db:
    image: postgres:13
    container_name: sonarqube-db
    networks:
      - sonarnet
    environment:
      - POSTGRES_USER=sonar
      - POSTGRES_PASSWORD=sonar
      - POSTGRES_DB=sonar
    volumes:
      - postgresql_data:/var/lib/postgresql/data
    restart: always

networks:
  sonarnet:
    driver: bridge

volumes:
  postgresql_data:
EOF

# Configure kernel settings required by SonarQube
echo "Configuring system settings for SonarQube..."
cat <<EOF | sudo tee -a /etc/sysctl.conf
vm.max_map_count=262144
fs.file-max=65536
EOF
sudo sysctl -p

# Configure SonarQube Scanner to use your SonarQube server
echo "sonar.host.url=http://localhost:9000" | sudo tee -a /opt/sonar-scanner/conf/sonar-scanner.properties

# Start SonarQube
echo "Starting SonarQube..."
cd /opt/sonarqube && sudo docker-compose up -d

# Install Trivy
echo "Installing Trivy..."
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install -y trivy

# Setup Prometheus and Grafana
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

# Install Grafana
echo "Installing Grafana..."
sudo apt-get install -y software-properties-common
sudo wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Enable and start Prometheus
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Create Jenkins agent node setup script
echo "Creating Jenkins agent setup script..."
cat <<EOF | sudo tee /opt/setup-jenkins-node.sh
#!/bin/bash

# This script helps set up a new Jenkins agent node

if [ \$# -ne 3 ]; then
  echo "Usage: \$0 <node-name> <node-description> <number-of-executors>"
  exit 1
fi

NODE_NAME=\$1
NODE_DESCRIPTION=\$2
EXECUTORS=\$3
JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_API_TOKEN=\$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

# Create the Jenkins agent user
sudo adduser --disabled-password --gecos "" jenkins-agent
sudo mkdir -p /home/jenkins-agent/.ssh
sudo touch /home/jenkins-agent/.ssh/authorized_keys

# Generate SSH key if it doesn't exist
if [ ! -f /var/lib/jenkins/.ssh/id_rsa ]; then
  sudo mkdir -p /var/lib/jenkins/.ssh
  sudo ssh-keygen -t rsa -b 4096 -f /var/lib/jenkins/.ssh/id_rsa -N ""
  sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh
fi

# Display the public key
echo "Add this public key to the authorized_keys file on the agent node:"
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub

# Wait for Jenkins to be fully up
until curl -s -f "\${JENKINS_URL}" > /dev/null; do
  echo "Waiting for Jenkins to start..."
  sleep 5
done

echo "Jenkins is up, continuing with node configuration..."

# Install Jenkins CLI
curl -sO "\${JENKINS_URL}/jnlpJars/jenkins-cli.jar"

# Create agent node configuration
cat <<EOG > node.xml
<?xml version="1.1" encoding="UTF-8"?>
<slave>
  <name>\${NODE_NAME}</name>
  <description>\${NODE_DESCRIPTION}</description>
  <remoteFS>/home/jenkins-agent</remoteFS>
  <numExecutors>\${EXECUTORS}</numExecutors>
  <mode>NORMAL</mode>
  <retentionStrategy class="hudson.slaves.RetentionStrategy\$Always"/>
  <launcher class="hudson.plugins.sshslaves.SSHLauncher" plugin="ssh-slaves">
    <host>IP_ADDRESS_OF_AGENT</host>
    <port>22</port>
    <credentialsId>jenkins-agent-key</credentialsId>
    <launchTimeoutSeconds>60</launchTimeoutSeconds>
    <maxNumRetries>10</maxNumRetries>
    <retryWaitTime>15</retryWaitTime>
    <sshHostKeyVerificationStrategy class="hudson.plugins.sshslaves.verifiers.NonVerifyingKeyVerificationStrategy"/>
  </launcher>
  <label>\${NODE_NAME}</label>
  <nodeProperties/>
</slave>
EOG

echo "Replace 'IP_ADDRESS_OF_AGENT' in the node.xml file with the actual IP of your agent node."
echo "Then use the following command to create the node in Jenkins:"
echo "java -jar jenkins-cli.jar -s \${JENKINS_URL} -auth \${JENKINS_USER}:\${JENKINS_API_TOKEN} create-node \${NODE_NAME} < node.xml"

echo "Node setup script created and ready to use!"
EOF
