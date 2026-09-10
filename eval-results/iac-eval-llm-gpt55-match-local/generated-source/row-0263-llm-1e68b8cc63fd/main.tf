terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to use for the provider configuration."
  type        = string
  default     = "us-east-1"
}

variable "iam_user_name" {
  description = "Name of the IAM user to create."
  type        = string
  default     = "basic-ssh-user"
}

variable "ssh_public_key" {
  description = "SSH public key to attach to the IAM user. Replace this with your actual SSH public key."
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7exampleplaceholderkeyonlydonotuseinproduction user@example"
}

resource "aws_iam_user" "basic_user" {
  name = var.iam_user_name

  tags = {
    Name        = var.iam_user_name
    Environment = "basic"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_user_ssh_key" "basic_user_ssh_key" {
  username   = aws_iam_user.basic_user.name
  encoding   = "SSH"
  public_key = var.ssh_public_key
}

output "iam_user_name" {
  description = "The name of the IAM user."
  value       = aws_iam_user.basic_user.name
}

output "iam_user_arn" {
  description = "The ARN of the IAM user."
  value       = aws_iam_user.basic_user.arn
}

output "iam_user_ssh_key_id" {
  description = "The SSH key ID attached to the IAM user."
  value       = aws_iam_user_ssh_key.basic_user_ssh_key.ssh_public_key_id
}