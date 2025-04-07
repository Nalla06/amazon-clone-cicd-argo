#!/bin/bash

# Define the AWS region
REGION="us-east-1"
export AWS_DEFAULT_REGION=$REGION
export AWS_REGION=$REGION

echo "Using AWS region: $AWS_REGION"

# Configuration
JENKINS_URL="http://localhost:8080"
JENKINS_CLI="/tmp/jenkins-cli.jar"

# Jenkins admin credentials
JENKINS_ADMIN_USERNAME="admin"
JENKINS_ADMIN_PASSWORD="admin"  # Replace with your Jenkins admin password

# Download Jenkins CLI
echo "Downloading Jenkins CLI..."
wget -q "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -O $JENKINS_CLI

# Retrieve credentials from AWS Parameter Store
echo "Retrieving credentials from AWS Parameter Store..."
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

// Get Jenkins instance
def jenkins = Jenkins.get() 

// Get credentials store
def domain = Domain.global()
def store = jenkins.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

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
// Using the correct constructor for AWSCredentialsImpl
def awsCredentials = new AWSCredentialsImpl(
  CredentialsScope.GLOBAL,
  "aws-ecr-credentials",
  "AWS Credentials for ECR",
  "$AWS_ACCESS_KEY",
  "$AWS_SECRET_KEY",
  "",  // IAM Role to use (empty for using access/secret keys)
  ""   // Description (optional)
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
java -jar $JENKINS_CLI -auth $JENKINS_ADMIN_USERNAME:$JENKINS_ADMIN_PASSWORD -s $JENKINS_URL groovy = < /tmp/add-credentials.groovy

# Verify credentials
echo "Verifying credentials..."
cat << 'EOF' | java -jar $JENKINS_CLI -auth $JENKINS_ADMIN_USERNAME:$JENKINS_ADMIN_PASSWORD -s $JENKINS_URL groovy =
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.common.StandardCredentials

def jenkins = Jenkins.get()
def creds = CredentialsProvider.lookupCredentials(
  StandardCredentials.class,
  jenkins
)
println("Found ${creds.size()} credentials:")
creds.each { c -> println("- ID: ${c.id}, Description: ${c.description}") }
EOF

# Clean up
echo "Cleaning up temporary files..."
rm $JENKINS_CLI /tmp/add-credentials.groovy

echo "Jenkins credentials setup complete!"