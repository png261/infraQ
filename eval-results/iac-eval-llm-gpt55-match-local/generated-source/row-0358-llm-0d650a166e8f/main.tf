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

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "basic-lightsail-instance"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID for the operating system or application."
  type        = string
  default     = "ubuntu_22_04"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining instance size and pricing."
  type        = string
  default     = "nano_3_0"
}

resource "aws_lightsail_instance" "basic" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = {
    Name        = var.instance_name
    Environment = "basic"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_static_ip" "basic" {
  name = "${var.instance_name}-static-ip"
}

resource "aws_lightsail_static_ip_attachment" "basic" {
  static_ip_name = aws_lightsail_static_ip.basic.name
  instance_name  = aws_lightsail_instance.basic.name
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.basic.name
}

output "lightsail_availability_zone" {
  description = "Availability zone of the Lightsail instance."
  value       = aws_lightsail_instance.basic.availability_zone
}

output "lightsail_static_ip" {
  description = "Static public IP address attached to the Lightsail instance."
  value       = aws_lightsail_static_ip.basic.ip_address
}