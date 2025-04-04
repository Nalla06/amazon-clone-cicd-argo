#!/bin/bash

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
sudo usermod -aG docker ubuntu

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
rm sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip

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
sudo useradd --no-create-home --shell /bin/false prometheus
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

sudo chmod +x /opt/setup-jenkins-node.sh

# Create Docker-based Jenkins agent script
echo "Creating Docker-based Jenkins agent script..."
cat <<EOF | sudo tee /opt/create-jenkins-agent-container.sh
#!/bin/bash

# This script helps create a Jenkins agent using Docker

if [ \$# -ne 2 ]; then
  echo "Usage: \$0 <node-name> <number-of-executors>"
  exit 1
fi

NODE_NAME=\$1
EXECUTORS=\$2
JENKINS_URL="http://\$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8080"

# Create agent working directory
sudo mkdir -p /var/jenkins-agents/\${NODE_NAME}
sudo chown 1000:1000 /var/jenkins-agents/\${NODE_NAME}

# Create Docker agent
docker run -d --name jenkins-agent-\${NODE_NAME} \
  -v /var/jenkins-agents/\${NODE_NAME}:/home/jenkins/agent \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e JENKINS_URL=\${JENKINS_URL} \
  -e JENKINS_AGENT_NAME=\${NODE_NAME} \
  -e JENKINS_SECRET=<agent-secret> \
  -e JENKINS_AGENT_WORKDIR=/home/jenkins/agent \
  --restart always \
  jenkins/inbound-agent:latest

echo "Docker-based Jenkins agent '\${NODE_NAME}' created!"
echo "Note: Replace <agent-secret> with the actual agent secret from Jenkins"
echo "You can get this by creating a node in Jenkins UI and checking its connection info"
EOF

sudo chmod +x /opt/create-jenkins-agent-container.sh

# Install additional Jenkins plugins
echo "Installing Jenkins plugins..."
sudo mkdir -p /var/lib/jenkins/init.groovy.d/
cat <<EOF | sudo tee /var/lib/jenkins/init.groovy.d/install-plugins.groovy
import jenkins.model.*
import hudson.security.*
import hudson.util.*;
import jenkins.install.*;
import java.util.logging.Logger

def logger = Logger.getLogger("")
def installed = false
def initialized = false

def pluginParameter = "blueocean docker-workflow pipeline-github-lib git terraform sonar aws-credentials amazon-ecr prometheus ssh-slaves docker-plugin metrics"
def plugins = pluginParameter.split()

logger.info("Downloading and installing plugins")
def instance = Jenkins.getInstance()
def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()
uc.updateAllSites()

plugins.each { plugin ->
  if (!pm.getPlugin(plugin)) {
    logger.info("Installing \${plugin}")
    def installFuture = uc.getPlugin(plugin).deploy()
    while(!installFuture.isDone()) {
      logger.info("Waiting for plugin \${plugin} to be installed")
      Thread.sleep(3000)
    }
  }
}

instance.save()
logger.info("Plugin installation complete.")
EOF

sudo chown jenkins:jenkins /var/lib/jenkins/init.groovy.d/install-plugins.groovy

# Configure Jenkins global security
cat <<EOF | sudo tee /var/lib/jenkins/init.groovy.d/security.groovy
import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.getInstance()

// Enable agent to master access control
instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)

// Disable JNLP (not using JNLP)
instance.setSlaveAgentPort(0)

instance.save()
EOF

sudo chown jenkins:jenkins /var/lib/jenkins/init.groovy.d/security.groovy

# Restart Jenkins to apply changes
sudo systemctl restart jenkins

# Final setup and permissions
echo "Finalizing setup..."
sudo chown -R ubuntu:ubuntu /home/ubuntu

# Print installation summary
echo "==================================================================="
echo "Installation complete! The following tools are now available:"
echo "- GitHub (git client)"
echo "- Jenkins (with agent node capability)"
echo "- SonarQube Scanner"
echo "- Aqua Trivy"
echo "- Docker"
echo "- AWS CLI"
echo "- Terraform"
echo "- Prometheus & Grafana"
echo "==================================================================="
echo ""
echo "Access URLs:"
echo "- Jenkins: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "- Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "- Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo ""
echo "Jenkins initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo ""
echo "==================================================================="
echo "To set up a Jenkins agent node, use:"
echo "sudo /opt/setup-jenkins-node.sh <node-name> <node-description> <executors>"
echo ""
echo "To create a Docker-based Jenkins agent, use:"
echo "sudo /opt/create-jenkins-agent-container.sh <node-name> <executors>"
echo "==================================================================="