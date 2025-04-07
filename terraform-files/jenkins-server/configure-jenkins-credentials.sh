#!/bin/bash
REGION=$(curl -s --connect-timeout 5 http://169.254.169.254/latest/meta-data/placement/region || echo "")

# If metadata service doesn't respond, use a fallback region
if [ -z "$REGION" ]; then
  # Replace with your actual AWS region
  REGION="us-east-1"  # Use your preferred region here
fi

# Export the region for AWS CLI
export AWS_DEFAULT_REGION=$REGION
export AWS_REGION=$REGION

echo "Using AWS region: $AWS_REGION"
# Wait for Jenkins to be fully up and running
echo "Waiting for Jenkins to become available..."
timeout 300 bash -c 'until curl -s -f http://localhost:8080 > /dev/null; do sleep 5; done'

#!/bin/bash

# Configuration
JENKINS_URL="http://localhost:8080"

# Get Jenkins admin password
JENKINS_ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
echo "Jenkins admin password: $JENKINS_ADMIN_PASSWORD"

# Install Trivy
echo "Installing Trivy..."
sudo apt-get update
sudo apt-get install -y wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install -y trivy

echo "Trivy installation complete. Version:"
trivy --version

# Download Jenkins CLI
echo "Downloading Jenkins CLI..."
wget -q "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -O /tmp/jenkins-cli.jar

# Install necessary Jenkins plugins
echo "Installing required Jenkins plugins..."
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s $JENKINS_URL install-plugin credentials credentials-binding plain-credentials aws-credentials

echo "Restarting Jenkins to apply plugins..."
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s $JENKINS_URL safe-restart

echo "Waiting for Jenkins to restart..."
sleep 60
timeout 300 bash -c "until curl -s -f $JENKINS_URL > /dev/null; do sleep 5; done"
echo "Jenkins is back online"

# Get credentials from AWS Parameter Store
echo "Retrieving credentials from AWS Parameter Store..."
# Get current AWS region
REGION=$(curl -s --connect-timeout 5 http://169.254.169.254/latest/meta-data/placement/region || echo "us-east-1")
echo "Using AWS region: $REGION"

# Retrieve credentials from Parameter Store
GITHUB_USERNAME=$(aws ssm get-parameter --region $REGION --name "/jenkins/github/username" --with-decryption --query "Parameter.Value" --output text)
GITHUB_TOKEN=$(aws ssm get-parameter --region $REGION --name "/jenkins/github/token" --with-decryption --query "Parameter.Value" --output text)
SONAR_TOKEN=$(aws ssm get-parameter --region $REGION --name "/jenkins/sonarqube/token" --with-decryption --query "Parameter.Value" --output text)
DOCKER_USERNAME=$(aws ssm get-parameter --region $REGION --name "/jenkins/docker/username" --with-decryption --query "Parameter.Value" --output text)
DOCKER_PASSWORD=$(aws ssm get-parameter --region $REGION --name "/jenkins/docker/password" --with-decryption --query "Parameter.Value" --output text)
AWS_ACCESS_KEY=$(aws ssm get-parameter --region $REGION --name "/jenkins/aws/access-key" --with-decryption --query "Parameter.Value" --output text)
AWS_SECRET_KEY=$(aws ssm get-parameter --region $REGION --name "/jenkins/aws/secret-key" --with-decryption --query "Parameter.Value" --output text)

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

// Create GitHub credentials
def githubCredentials = new UsernamePasswordCredentialsImpl(
  CredentialsScope.GLOBAL,
  "github-credentials",
  "GitHub Access",
  "$GITHUB_USERNAME",
  "$GITHUB_TOKEN"
)

// Create SonarQube token
def sonarToken = new StringCredentialsImpl(
  CredentialsScope.GLOBAL,
  "sonarqube-token",
  "SonarQube Scanner Token",
  Secret.fromString("$SONAR_TOKEN")
)

// Create Docker Hub credentials
def dockerCredentials = new UsernamePasswordCredentialsImpl(
  CredentialsScope.GLOBAL,
  "docker-hub-credentials",
  "Docker Hub Access",
  "$DOCKER_USERNAME",
  "$DOCKER_PASSWORD"
)

// Create AWS ECR credentials
def awsCredentials = new AWSCredentialsImpl(
  CredentialsScope.GLOBAL,
  "aws-ecr-credentials",
  "AWS Credentials for ECR",
  "$AWS_ACCESS_KEY",
  "$AWS_SECRET_KEY",
  ""
)

// Add all credentials to store
store.addCredentials(domain, githubCredentials)
store.addCredentials(domain, sonarToken)
store.addCredentials(domain, dockerCredentials)
store.addCredentials(domain, awsCredentials)

println "All credentials added successfully!"
EOF

# Execute Groovy script to add credentials
echo "Adding credentials to Jenkins..."
cat /tmp/add-credentials.groovy | java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s $JENKINS_URL groovy =

# Verify credentials were added
echo "Verifying credentials..."
cat << 'EOF' | java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s $JENKINS_URL groovy =
def creds = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
  com.cloudbees.plugins.credentials.common.StandardCredentials.class,
  Jenkins.instance
)
println("Found ${creds.size()} credentials:")
creds.each { c -> println("- ID: ${c.id}, Description: ${c.description}") }
EOF

# Clean up
echo "Cleaning up temporary files..."
rm /tmp/jenkins-cli.jar /tmp/add-credentials.groovy

echo "Jenkins credentials and Trivy setup complete!"