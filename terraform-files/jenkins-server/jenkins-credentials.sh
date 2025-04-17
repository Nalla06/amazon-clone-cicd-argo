#!/bin/bash

# Set Jenkins and AWS parameters
JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_API_TOKEN="xxxxxxxxxx"
JENKINS_CLI_JAR="/tmp/jenkins-cli.jar"
REGION="us-east-1"

# Download Jenkins CLI if not already available
if [ ! -f "$JENKINS_CLI_JAR" ]; then
  echo "Downloading Jenkins CLI..."
  wget -q "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -O "$JENKINS_CLI_JAR"
fi

# Test Jenkins CLI Authentication
echo "Testing Jenkins CLI authentication..."
java -jar "$JENKINS_CLI_JAR" -auth "$JENKINS_USER:$JENKINS_API_TOKEN" -s "$JENKINS_URL" who-am-i
if [ $? -ne 0 ]; then
  echo "Authentication failed! Please check your username and API token."
  exit 1
fi

# Retrieve credentials from AWS Parameter Store
echo "Retrieving credentials from AWS Parameter Store..."
GITHUB_USERNAME=$(aws ssm get-parameter --region "$REGION" --name "/jenkins/github/username" --with-decryption --query "Parameter.Value" --output text)
GITHUB_TOKEN=$(aws ssm get-parameter --region "$REGION" --name "/jenkins/github/token" --with-decryption --query "Parameter.Value" --output text)
DOCKER_USERNAME=$(aws ssm get-parameter --region "$REGION" --name "/jenkins/docker/username" --with-decryption --query "Parameter.Value" --output text)
DOCKER_PASSWORD=$(aws ssm get-parameter --region "$REGION" --name "/jenkins/docker/password" --with-decryption --query "Parameter.Value" --output text)
AWS_ACCESS_KEY=$(aws ssm get-parameter --region "$REGION" --name "/jenkins/aws/access-key" --with-decryption --query "Parameter.Value" --output text)
AWS_SECRET_KEY=$(aws ssm get-parameter --region "$REGION" --name "/jenkins/aws/secret-key" --with-decryption --query "Parameter.Value" --output text)

# Add GitHub credentials
echo "Adding GitHub credentials to Jenkins..."
cat > /tmp/add-github-credentials.groovy << EOF
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import hudson.util.Secret

def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

def githubCredentials = new UsernamePasswordCredentialsImpl(
  CredentialsScope.GLOBAL,
  "github-credentials-id",
  "GitHub Credentials",
  "$GITHUB_USERNAME",
  "$GITHUB_TOKEN"
)

store.addCredentials(domain, githubCredentials)
println "GitHub credentials added successfully!"
EOF
cat /tmp/add-github-credentials.groovy | java -jar "$JENKINS_CLI_JAR" -auth "$JENKINS_USER:$JENKINS_API_TOKEN" -s "$JENKINS_URL" groovy =

# Add Docker credentials
echo "Adding Docker credentials to Jenkins..."
cat > /tmp/add-docker-credentials.groovy << EOF
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import hudson.util.Secret

def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

def dockerCredentials = new UsernamePasswordCredentialsImpl(
  CredentialsScope.GLOBAL,
  "docker-credentials-id",
  "Docker Credentials",
  "$DOCKER_USERNAME",
  "$DOCKER_PASSWORD"
)

store.addCredentials(domain, dockerCredentials)
println "Docker credentials added successfully!"
EOF
cat /tmp/add-docker-credentials.groovy | java -jar "$JENKINS_CLI_JAR" -auth "$JENKINS_USER:$JENKINS_API_TOKEN" -s "$JENKINS_URL" groovy =

# Add AWS credentials
echo "Adding AWS credentials to Jenkins..."
cat > /tmp/add-aws-credentials.groovy << EOF
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl

def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

def awsCredentials = new AWSCredentialsImpl(
  CredentialsScope.GLOBAL,
  "aws-credentials-id",
  "$AWS_ACCESS_KEY",
  "$AWS_SECRET_KEY",
  "AWS Credentials for Jenkins"
)

store.addCredentials(domain, awsCredentials)
println "AWS credentials added successfully!"
EOF
cat /tmp/add-aws-credentials.groovy | java -jar "$JENKINS_CLI_JAR" -auth "$JENKINS_USER:$JENKINS_API_TOKEN" -s "$JENKINS_URL" groovy =

# Clean up temporary files
rm -f /tmp/add-github-credentials.groovy /tmp/add-docker-credentials.groovy /tmp/add-aws-credentials.groovy

echo "All credentials have been added to Jenkins successfully!"