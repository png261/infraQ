terraform {
  required_version = ">= 1.5.0"

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
  description = "AWS region where the latest Amazon Linux 2 AMI should be looked up."
  type        = string
  default     = "us-east-1"
}

data "aws_ami" "latest_amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    values = [
      "amzn2-ami-hvm-*-x86_64-gp2"
    ]
  }

  filter {
    name = "architecture"
    values = [
      "x86_64"
    ]
  }

  filter {
    name = "virtualization-type"
    values = [
      "hvm"
    ]
  }

  filter {
    name = "root-device-type"
    values = [
      "ebs"
    ]
  }

  filter {
    name = "state"
    values = [
      "available"
    ]
  }
}

output "amazon_linux_2_ami_id" {
  description = "The ID of the latest Amazon Linux 2 AMI."
  value       = data.aws_ami.latest_amazon_linux_2.id
}

output "amazon_linux_2_ami_name" {
  description = "The name of the latest Amazon Linux 2 AMI."
  value       = data.aws_ami.latest_amazon_linux_2.name
}

output "amazon_linux_2_ami_owner_id" {
  description = "The AWS account ID that owns the AMI."
  value       = data.aws_ami.latest_amazon_linux_2.owner_id
}

output "amazon_linux_2_ami_creation_date" {
  description = "The creation date of the latest Amazon Linux 2 AMI."
  value       = data.aws_ami.latest_amazon_linux_2.creation_date
}