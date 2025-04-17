#!/bin/bash

# === PART 1: Install Jenkins, SonarQube, and Required Tools ===

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
    git \
    openjdk-17-jdk

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

# Wait for Jenkins to become available
echo "Waiting for Jenkins to start..."
timeout 300 bash -c 'until curl -s -f http://localhost:8080 > /dev/null; do echo "Waiting for Jenkins..."; sleep 5; done'
echo "Jenkins is up and running!"

# === PART 2: Install and Configure SonarQube ===

# Install SonarQube Server using Docker
echo "Installing SonarQube Server using Docker..."
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
    image: sonarqube:9.9.0-community
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

# Start SonarQube
echo "Starting SonarQube..."
cd /opt/sonarqube && sudo docker-compose up -d

# Wait for SonarQube to become ready
echo "Waiting for SonarQube to become available..."
timeout 300 bash -c 'until curl -s -f http://localhost:9000/api/system/status | grep -q "UP"; do echo "Waiting for SonarQube..."; sleep 10; done'
echo "SonarQube is up and running at http://localhost:9000"

# === PART 3: Configure Jenkins ===

# Get Jenkins admin password
JENKINS_ADMIN_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
echo "Jenkins admin password: $JENKINS_ADMIN_PASSWORD"
echo "Please use this password for initial Jenkins setup at http://your-server-ip:8080"

# Download Jenkins CLI
echo "Downloading Jenkins CLI..."
wget -q "http://localhost:8080/jnlpJars/jenkins-cli.jar" -O /tmp/jenkins-cli.jar

# Install required Jenkins plugins
echo "Installing required Jenkins plugins..."
cat > /tmp/install-plugins.groovy << 'EOF'
import jenkins.model.*
import hudson.util.*

def instance = Jenkins.getInstance()
def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()
uc.updateAllSites()

def plugins = [
  "credentials",
  "credentials-binding",
  "plain-credentials",
  "aws-credentials",
  "docker-workflow",
  "workflow-aggregator",
  "git",
  "blueocean",
  "pipeline-github-lib",
  "terraform",
  "sonar",
  "sonarqube-scanner",
  "prometheus",
  "ssh-slaves",
  "docker-plugin",
  "metrics",
  "amazon-ecr",
  "nodejs",
  "pipeline-aws",
  "pipeline-stage-view" 
]
plugins.each { plugin ->
  if (!pm.getPlugin(plugin)) {
    println "Installing ${plugin}..."
    def installFuture = uc.getPlugin(plugin).deploy()
    while(!installFuture.isDone()) {
      println "Waiting for plugin installation: ${plugin}"
      sleep(1000)
    }
  } else {
    println "Plugin ${plugin} already installed."
  }
}

instance.save()
println "Plugins installation completed!"
EOF

cat /tmp/install-plugins.groovy | java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 groovy =

# Restart Jenkins to apply plugin changes
echo "Restarting Jenkins to apply plugin changes..."
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 safe-restart

echo "Waiting for Jenkins to restart..."
sleep 30
timeout 100 bash -c 'until curl -s -f http://localhost:8080 > /dev/null; do echo "Waiting for Jenkins restart..."; sleep 5; done'
echo "Jenkins successfully restarted!"

# === PART 4: Integrate Jenkins with SonarQube ===

# Generate SonarQube token
echo "Generating SonarQube token for Jenkins integration..."
SONAR_USER="admin"
SONAR_PASSWORD="admin"

# Login to SonarQube and generate a token
curl -X POST -c /tmp/cookies.txt "http://localhost:9000/api/authentication/login" -d "login=$SONAR_USER&password=$SONAR_PASSWORD"
TOKEN_RESPONSE=$(curl -s -X POST -b /tmp/cookies.txt "http://localhost:9000/api/user_tokens/generate" -d "name=jenkins-integration")
SONAR_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"token":"[^"]*' | awk -F':' '{print $2}' | tr -d '"')

if [ -z "$SONAR_TOKEN" ]; then
  echo "Failed to get SonarQube token. You may need to create one manually."
else
  echo "SonarQube token generated successfully!"
  echo "SonarQube Token: $SONAR_TOKEN"
  
  # Add SonarQube token to Jenkins credentials
  echo "Adding SonarQube token to Jenkins credentials..."
  cat > /tmp/add-sonar-credential.groovy << EOF
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.plaincredentials.impl.*
import hudson.util.Secret

def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

def sonarToken = new StringCredentialsImpl(
  CredentialsScope.GLOBAL,
  "sonarqube-token",
  "SonarQube Scanner Token",
  Secret.fromString("$SONAR_TOKEN")
)

store.addCredentials(domain, sonarToken)
println "SonarQube token added to Jenkins credentials"
EOF

  cat /tmp/add-sonar-credential.groovy | java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 groovy =
fi

rm -f /tmp/cookies.txt /tmp/add-sonar-credential.groovy

# Final Messages
echo "===== Jenkins and SonarQube Setup Complete! ====="
echo "Jenkins is running at http://localhost:8080"
echo "Initial admin password: $JENKINS_ADMIN_PASSWORD"
echo "SonarQube is running at http://localhost:9000 (default credentials: admin/admin)"