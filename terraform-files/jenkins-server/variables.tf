variable "my-key" {
  description = "The SSH key for the instance"
  type        = string
}

variable "server_name" {
  description = "The name for the server"
  type        = string
}

variable "ami" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
}

variable "key_name" {
  description = "Key name for SSH access"
  type        = string
}

variable "volume_size" {
  description = "Volume size"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
