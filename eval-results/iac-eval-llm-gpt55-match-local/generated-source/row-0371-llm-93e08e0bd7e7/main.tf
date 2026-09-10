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
  description = "AWS region where the Lightsail disk will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail disk."
  type        = string
  default     = "us-east-1a"
}

variable "disk_name" {
  description = "Name of the Lightsail disk."
  type        = string
  default     = "example-lightsail-disk"
}

variable "disk_size_gb" {
  description = "Size of the Lightsail disk in GB."
  type        = number
  default     = 32
}

resource "aws_lightsail_disk" "example" {
  name              = var.disk_name
  size_in_gb        = var.disk_size_gb
  availability_zone = var.availability_zone

  tags = {
    Name        = var.disk_name
    Environment = "example"
    ManagedBy   = "Terraform"
  }
}

output "lightsail_disk_name" {
  description = "The name of the created Lightsail disk."
  value       = aws_lightsail_disk.example.name
}

output "lightsail_disk_arn" {
  description = "The ARN of the created Lightsail disk."
  value       = aws_lightsail_disk.example.arn
}

output "lightsail_disk_availability_zone" {
  description = "The availability zone of the Lightsail disk."
  value       = aws_lightsail_disk.example.availability_zone
}