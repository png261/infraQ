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
  description = "Name of the Lightsail instance."
  type        = string
  default     = "example-lightsail-instance"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID."
  type        = string
  default     = "ubuntu_22_04"
}

variable "bundle_id" {
  description = "Lightsail bundle ID."
  type        = string
  default     = "nano_3_0"
}

variable "snapshot_time_of_day" {
  description = "Time of day in UTC for automatic Lightsail snapshots. Format must be HH:00."
  type        = string
  default     = "06:00"
}

resource "aws_lightsail_instance" "this" {
  name              = var.lightsail_instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  add_on {
    type                 = "AutoSnapshot"
    snapshot_time_of_day = var.snapshot_time_of_day
    status               = "Enabled"
  }

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "example"
    ManagedBy   = "Terraform"
  }
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.this.name
}

output "lightsail_instance_arn" {
  description = "ARN of the Lightsail instance."
  value       = aws_lightsail_instance.this.arn
}

output "lightsail_public_ip_address" {
  description = "Public IP address of the Lightsail instance."
  value       = aws_lightsail_instance.this.public_ip_address
}

output "auto_snapshot_status" {
  description = "Auto snapshot status for the Lightsail instance."
  value       = "Enabled"
}