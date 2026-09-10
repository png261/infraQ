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
  description = "AWS region where the Lightsail instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "lightsail_instance_name" {
  description = "Name of the AWS Lightsail instance."
  type        = string
  default     = "default-lightsail-instance"
}

variable "lightsail_availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "lightsail_blueprint_id" {
  description = "Lightsail blueprint ID. Default is Amazon Linux 2."
  type        = string
  default     = "amazon_linux_2"
}

variable "lightsail_bundle_id" {
  description = "Lightsail bundle ID defining instance size."
  type        = string
  default     = "nano_3_0"
}

resource "aws_lightsail_instance" "default" {
  name              = var.lightsail_instance_name
  availability_zone = var.lightsail_availability_zone
  blueprint_id      = var.lightsail_blueprint_id
  bundle_id         = var.lightsail_bundle_id

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "default"
    ManagedBy   = "Terraform"
  }
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.default.name
}

output "lightsail_instance_arn" {
  description = "ARN of the Lightsail instance."
  value       = aws_lightsail_instance.default.arn
}

output "lightsail_public_ip" {
  description = "Public IP address of the Lightsail instance."
  value       = aws_lightsail_instance.default.public_ip_address
}

output "lightsail_blueprint_id" {
  description = "Blueprint used by the Lightsail instance."
  value       = aws_lightsail_instance.default.blueprint_id
}

output "lightsail_bundle_id" {
  description = "Bundle used by the Lightsail instance."
  value       = aws_lightsail_instance.default.bundle_id
}