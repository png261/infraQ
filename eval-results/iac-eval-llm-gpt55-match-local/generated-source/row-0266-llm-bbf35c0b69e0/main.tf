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
  description = "AWS region used for the provider configuration."
  type        = string
  default     = "us-east-1"
}

variable "virtual_mfa_device_name" {
  description = "The name of the IAM virtual MFA device."
  type        = string
  default     = "basic-virtual-mfa-device"
}

resource "aws_iam_virtual_mfa_device" "basic" {
  virtual_mfa_device_name = var.virtual_mfa_device_name

  tags = {
    Name        = var.virtual_mfa_device_name
    Environment = "basic"
    ManagedBy   = "Terraform"
  }
}

output "virtual_mfa_device_arn" {
  description = "The ARN of the IAM virtual MFA device."
  value       = aws_iam_virtual_mfa_device.basic.arn
}

output "virtual_mfa_device_name" {
  description = "The name of the IAM virtual MFA device."
  value       = aws_iam_virtual_mfa_device.basic.virtual_mfa_device_name
}