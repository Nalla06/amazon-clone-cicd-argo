provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "ssh_private_key" {
  name            = "/ssh/linux-key-pair"  # The name of your stored private key
  with_decryption = true
}

# ECR Repository for amazon-clone
resource "aws_ecr_repository" "amazon_clone" {
  name                 = "amazon-clone"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "amazon-clone"
    Environment = "production"
  }
}

# ECR Repository Lifecycle Policy to manage images
resource "aws_ecr_lifecycle_policy" "amazon_clone_policy" {
  repository = aws_ecr_repository.amazon_clone.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 10 images",
      selection = {
        tagStatus     = "any",
        countType     = "imageCountMoreThan",
        countNumber   = 10
      },
      action = {
        type = "expire"
      }
    }]
  })
}

# STEP 1: Setting up a Security Group with necessary ports
resource "aws_security_group" "my_security_group" {
  name        = "my-jenkins-sg"
  description = "Allow necessary ports for Jenkins, Docker, and Kubernetes"

  # Allow SSH for remote server management
  ingress {
    description     = "SSH Access"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access
  ingress {
    description     = "HTTP Port"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS connections
  ingress {
    description     = "HTTPS Port"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Port 2379-2380 is required for etcd-cluster
  ingress {
    description     = "etc-cluster Port"
    from_port       = 2379
    to_port         = 2380
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 3000 is required for Grafana
  ingress {
    description     = "NPM Port"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 6443 is required for KubeAPIServer
  ingress {
    description     = "Kube API Server"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 8080 is required for Jenkins
  ingress {
    description     = "Jenkins Port"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 9000 is required for SonarQube
  ingress {
    description     = "SonarQube Port"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 9090 is required for Prometheus
  ingress {
    description     = "Prometheus Port"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 9100 is required for Prometheus metrics server
  ingress {
    description     = "Prometheus Metrics Port"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  # Port 10250-10260 is required for K8s
  ingress {
    description     = "K8s Ports"
    from_port       = 10250
    to_port         = 10260
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Port 30000-32767 is required for NodePort
  ingress {
    description     = "K8s NodePort"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  # Define outbound rules to allow all
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "jenkins_ssm_role" {
  name = "jenkins_ssm_access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_ssm_policy" {
  name = "jenkins_ssm_policy"
  role = aws_iam_role.jenkins_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/ssh/*",  
          "arn:aws:ssm:*:*:parameter/jenkins/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken"
        ],
        Resource = [
          aws_ecr_repository.amazon_clone.arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins_instance_profile"
  role = aws_iam_role.jenkins_ssm_role.name
}

resource "aws_instance" "jenkins_server" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.my_security_group.id]
  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.id 
  root_block_device {
    volume_size = var.volume_size
  }

  tags = {
    Name = var.server_name
  }
  
  provisioner "file" {
    source      = "./install-script.sh"
    destination = "/tmp/install-script.sh"
    connection {
      type        = "ssh"
      private_key = data.aws_ssm_parameter.ssh_private_key.value
      user        = "ubuntu"
      host        = self.public_ip
    }
  }
  
  provisioner "file" {
    source      = "./configure-jenkins-credentials.sh"  # Add this new file
    destination = "/tmp/configure-jenkins-credentials.sh"
    connection {
      type        = "ssh"
      private_key = data.aws_ssm_parameter.ssh_private_key.value
      user        = "ubuntu"
      host        = self.public_ip
    }
  }
  
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = data.aws_ssm_parameter.ssh_private_key.value
      host        = self.public_ip
    }

    inline = [
      "chmod +x /tmp/install-script.sh",
      "sudo /tmp/install-script.sh",
      "chmod +x /tmp/configure-jenkins-credentials.sh",
      "sudo /tmp/configure-jenkins-credentials.sh"  # Run the credentials script after installation
    ]
  }
}

output "public_ip_address" {
  value = "${aws_instance.jenkins_server.public_ip}"
}

output "private_ip_address" {
  value = "${aws_instance.jenkins_server.private_ip}"
}

output "ecr_repository_url" {
  value = "${aws_ecr_repository.amazon_clone.repository_url}"
  description = "The URL of the amazon-clone ECR repository"
}