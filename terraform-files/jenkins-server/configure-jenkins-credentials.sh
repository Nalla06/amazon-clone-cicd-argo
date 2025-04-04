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

# Get Jenkins admin password
JENKINS_ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
echo "Jenkins admin password: $JENKINS_ADMIN_PASSWORD"

# Download the Jenkins CLI jar
echo "Downloading Jenkins CLI..."
wget -q http://localhost:8080/jnlpJars/jenkins-cli.jar -O /tmp/jenkins-cli.jar

# Install necessary Jenkins plugins (Credentials Plugin and AWS Credentials Plugin)
echo "Installing necessary Jenkins plugins (Credentials Plugin and AWS Credentials Plugin)..."
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 install-plugin credentials aws-credentials


# Wait for Jenkins to finish initialization
echo "Waiting for Jenkins plugins installation to complete..."
sleep 120  # Give time for plugin installation to complete

# Get credentials from AWS Parameter Store
echo "Retrieving credentials from AWS Parameter Store..."
GITHUB_USERNAME=$(aws ssm get-parameter --region $AWS_REGION --name "/jenkins/github/username" --with-decryption --query "Parameter.Value" --output text)
GITHUB_TOKEN=$(aws ssm get-parameter --region $AWS_REGION --name "/jenkins/github/token" --with-decryption --query "Parameter.Value" --output text)
SONAR_TOKEN=$(aws ssm get-parameter --region $AWS_REGION --name "/jenkins/sonarqube/token" --with-decryption --query "Parameter.Value" --output text)
DOCKER_USERNAME=$(aws ssm get-parameter --region $AWS_REGION  --name "/jenkins/docker/username" --with-decryption --query "Parameter.Value" --output text)
DOCKER_PASSWORD=$(aws ssm get-parameter --region $AWS_REGION --name "/jenkins/docker/password" --with-decryption --query "Parameter.Value" --output text)
AWS_ACCESS_KEY=$(aws ssm get-parameter --region $AWS_REGION --name "/jenkins/aws/access-key" --with-decryption --query "Parameter.Value" --output text)
AWS_SECRET_KEY=$(aws ssm get-parameter --region $AWS_REGION --name "/jenkins/aws/secret-key" --with-decryption --query "Parameter.Value" --output text)

# Create credential configuration scripts
echo "Creating credential configuration scripts..."

# GitHub credentials
cat > /tmp/github-credentials.groovy  << EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>github-credentials</id>
  <description>GitHub Access</description>
  <username>${GITHUB_USERNAME}</username>
  <password>${GITHUB_TOKEN}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF

# SonarQube token
cat > /tmp/sonarqube-credentials.groovy << EOF
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>sonarqube-token</id>
  <description>SonarQube Scanner Token</description>
  <secret>${SONAR_TOKEN}</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
EOF

# Docker Hub credentials
cat > /tmp/docker-credentials.groovy << EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>docker-hub-credentials</id>
  <description>Docker Hub Access</description>
  <username>${DOCKER_USERNAME}</username>
  <password>${DOCKER_PASSWORD}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF

# AWS credentials for ECR
cat > /tmp/aws-ecr-credentials.groovy << EOF
<com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>aws-ecr-credentials</id>
  <description>AWS Credentials for ECR</description>
  <accessKey>${AWS_ACCESS_KEY}</accessKey>
  <secretKey>${AWS_SECRET_KEY}</secretKey>
</com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl>
EOF

# Add all the credentials using the Jenkins CLI
echo "Adding credentials to Jenkins..."
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 create-credentials-by-groovy system::system::jenkins _ < /tmp/github-credentials.groovy
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 create-credentials-by-groovy system::system::jenkins _ < /tmp/sonarqube-credentials.groovy
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 create-credentials-by-groovy system::system::jenkins _ < /tmp/docker-credentials.groovy
java -jar /tmp/jenkins-cli.jar -auth admin:$JENKINS_ADMIN_PASSWORD -s http://localhost:8080 create-credentials-by-groovy system::system::jenkins _ < /tmp/aws-ecr-credentials.groovy

# Clean up temporary files
echo "Cleaning up..."
rm /tmp/jenkins-cli.jar /tmp/*-credentials.groovy

echo "Jenkins credentials have been configured successfully!"