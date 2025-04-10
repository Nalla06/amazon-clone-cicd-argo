#!/bin/bash

echo "Creating Docker-based Jenkins agent script..."
cat <<EOF > /opt/create-jenkins-agent-container.sh
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
mkdir -p /var/jenkins-agents/\${NODE_NAME}
chown 1000:1000 /var/jenkins-agents/\${NODE_NAME}

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

chmod +x /opt/create-jenkins-agent-container.sh

# Create improved SonarQube Jenkins integration script
echo "Creating SonarQube Jenkins integration script..."
cat <<EOF > /opt/configure-sonarqube-jenkins.sh
#!/bin/bash

# Wait for SonarQube to be fully up and running
echo "Waiting for SonarQube to become available..."
timeout 300 bash -c 'until curl -s -f http://localhost:9000/api/system/status | grep -q "UP"; do echo "Waiting for SonarQube..."; sleep 10; done'
echo "SonarQube is up and running!"

# Get Jenkins admin password
JENKINS_ADMIN_PASSWORD=\$(cat /var/lib/jenkins/secrets/initialAdminPassword)

# Generate SonarQube token
echo "Generating SonarQube token for Jenkins integration..."
# Default admin credentials for SonarQube
SONAR_USER="admin"
SONAR_PASSWORD="admin"

# Login to get cookies for authentication
curl -X POST -c /tmp/cookies.txt "http://localhost:9000/api/authentication/login" \
  -d "login=\${SONAR_USER}&password=\${SONAR_PASSWORD}"

# Generate token with cookies
TOKEN_RESPONSE=\$(curl -s -X POST -b /tmp/cookies.txt "http://localhost:9000/api/user_tokens/generate" \
  -d "name=jenkins-integration&login=admin")

# Extract token from response using more reliable JSON parsing
SONAR_TOKEN=\$(echo \$TOKEN_RESPONSE | grep -o '"token":"[^"]*' | awk -F':' '{print \$2}' | tr -d '"')

if [ -z "\$SONAR_TOKEN" ]; then
  echo "Failed to get SonarQube token. You may need to create one manually."
  echo "Go to SonarQube > My Account > Security > Generate Token"
else
  echo "SonarQube token generated successfully!"
  echo "SonarQube Token: \$SONAR_TOKEN"
  
  # Save the token to a file for reference
  cat <<EOG > /var/lib/jenkins/sonarqube-info.txt
SonarQube URL: http://localhost:9000
SonarQube Token: \$SONAR_TOKEN
EOG
  chown jenkins:jenkins /var/lib/jenkins/sonarqube-info.txt
  
  echo "SonarQube information saved to /var/lib/jenkins/sonarqube-info.txt"
  
  # Directly create the Jenkins credential for SonarQube
  cat > /tmp/add-sonar-credential.groovy << EOG
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.plaincredentials.impl.*
import hudson.util.Secret

// Get credentials store
def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// Create SonarQube token
def sonarToken = new StringCredentialsImpl(
  CredentialsScope.GLOBAL,
  "sonarqube-token",
  "SonarQube Scanner Token",
  Secret.fromString("$SONAR_TOKEN")
)

// Add the credential
store.addCredentials(domain, sonarToken)

println "SonarQube token added to Jenkins credentials"
EOG

  # Execute Groovy script to add SonarQube credential
  echo "Adding SonarQube token to Jenkins credentials..."
  cat /tmp/add-sonar-credential.groovy | java -jar /tmp/jenkins-cli.jar -auth admin:\$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 groovy =
  
  echo "SonarQube token has been automatically added to Jenkins credentials with ID: sonarqube-token"
fi

rm -f /tmp/cookies.txt /tmp/add-sonar-credential.groovy
EOF

chmod +x /opt/configure-sonarqube-jenkins.sh

# === PART 2: Configure Jenkins ===

# Determine AWS region
echo "Detecting AWS region..."
REGION=$(curl -s --connect-timeout 5 http://169.254.169.254/latest/meta-data/placement/region || echo "us-east-1")
export AWS_DEFAULT_REGION=$REGION
export AWS_REGION=$REGION
echo "Using AWS region: $AWS_REGION"

# Wait for Jenkins to be fully up and running
echo "Waiting for Jenkins to become available..."
timeout 300 bash -c 'until curl -s -f http://localhost:8080 > /dev/null; do echo "Waiting for Jenkins..."; sleep 5; done'
echo "Jenkins is up and running!"

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
timeout 200 bash -c 'until curl -s -f http://localhost:8080 > /dev/null; do echo "Waiting for Jenkins restart..."; sleep 5; done'
echo "Jenkins successfully restarted!"

# Set up credentials from AWS Parameter Store
echo "Setting up Jenkins credentials from AWS Parameter Store..."
echo "Retrieving credentials from AWS Parameter Store..."

# Check if AWS Parameter Store parameters exist
if aws ssm describe-parameters --region $REGION --parameter-filters "Key=Name,Values=/jenkins" &>/dev/null; then
  echo "Found Jenkins parameters in AWS Parameter Store, retrieving them..."
  
  # Retrieve credentials from AWS Parameter Store
  GITHUB_USERNAME=$(aws ssm get-parameter --region $REGION --name "/jenkins/github/username" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
  GITHUB_TOKEN=$(aws ssm get-parameter --region $REGION --name "/jenkins/github/token" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
  DOCKER_USERNAME=$(aws ssm get-parameter --region $REGION --name "/jenkins/docker/username" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
  DOCKER_PASSWORD=$(aws ssm get-parameter --region $REGION --name "/jenkins/docker/password" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
  AWS_ACCESS_KEY=$(aws ssm get-parameter --region $REGION --name "/jenkins/aws/access-key" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
  AWS_SECRET_KEY=$(aws ssm get-parameter --region $REGION --name "/jenkins/aws/secret-key" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
  
  # Create Groovy script to add credentials
  echo "Creating Groovy script to add credentials..."
  cat > /tmp/add-credentials.groovy << EOF
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.jenkins.plugins.awscredentials.*
import org.jenkinsci.plugins.plaincredentials.impl.*
import hudson.util.Secret

// Get credentials store
def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// Add credentials only if values are provided
List<Credentials> credentialsToAdd = []

// Create GitHub credentials
if ("$GITHUB_USERNAME" && "$GITHUB_TOKEN") {
  def githubCredentials = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "github-credentials",
    "GitHub Access",
    "$GITHUB_USERNAME",
    "$GITHUB_TOKEN"
  )
  credentialsToAdd.add(githubCredentials)
  println "Added GitHub credentials"
}

// Create Docker Hub credentials
if ("$DOCKER_USERNAME" && "$DOCKER_PASSWORD") {
  def dockerCredentials = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "docker-hub-credentials",
    "Docker Hub Access",
    "$DOCKER_USERNAME",
    "$DOCKER_PASSWORD"
  )
  credentialsToAdd.add(dockerCredentials)
  println "Added Docker Hub credentials"
}

// Create AWS ECR credentials
if ("$AWS_ACCESS_KEY" && "$AWS_SECRET_KEY") {
  def awsCredentials = new AWSCredentialsImpl(
    CredentialsScope.GLOBAL,
    "aws-ecr-credentials",
    "AWS Credentials for ECR",
    "$AWS_ACCESS_KEY",
    "$AWS_SECRET_KEY",
    ""
  )
  credentialsToAdd.add(awsCredentials)
  println "Added AWS ECR credentials"
}

// Add all credentials to store
credentialsToAdd.each { c ->
  store.addCredentials(domain, c)
}

println "Credentials setup complete!"
EOF

  # Execute Groovy script to add credentials
  echo "Adding credentials to Jenkins..."
  cat /tmp/add-credentials.groovy | java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 groovy =

  # Verify credentials were added
  echo "Verifying credentials..."
  cat << 'EOF' | java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 groovy =
def creds = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
  com.cloudbees.plugins.credentials.common.StandardCredentials.class,
  Jenkins.instance
)
println("Found ${creds.size()} credentials:")
creds.each { c -> println("- ID: ${c.id}, Description: ${c.description}") }
EOF

else
  echo "No Jenkins parameters found in AWS Parameter Store."
  echo "You need to create the following parameters in AWS Parameter Store for automatic credential setup:"
  echo "- /jenkins/github/username"
  echo "- /jenkins/github/token"
  echo "- /jenkins/docker/username"
  echo "- /jenkins/docker/password"
  echo "- /jenkins/aws/access-key"
  echo "- /jenkins/aws/secret-key"
  echo ""
  echo "You can set these up manually in Jenkins or create the parameters and run this script again."
fi

# Run SonarQube Jenkins integration script to generate a token
echo "Configuring SonarQube integration..."
/opt/configure-sonarqube-jenkins.sh

# Clean up temporary files
echo "Cleaning up temporary files..."
rm -f /tmp/jenkins-cli.jar /tmp/add-credentials.groovy /tmp/install-plugins.groovy

echo "===== DevOps Tools Setup Complete! ====="
echo "Jenkins is running at http://localhost:8080"
echo "Initial admin password: $JENKINS_ADMIN_PASSWORD"
echo "SonarQube is running at http://localhost:9000 (default credentials: admin/admin)"
echo "Prometheus is running at http://localhost:9090"
echo "Grafana is running at http://localhost:3000 (default credentials: admin/admin)"