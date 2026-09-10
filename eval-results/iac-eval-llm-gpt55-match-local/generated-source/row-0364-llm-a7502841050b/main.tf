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
  default     = "dualstack-lightsail-instance"
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

resource "aws_lightsail_instance" "dualstack_instance" {
  name              = var.lightsail_instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  ip_address_type = "dualstack"

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_instance_public_ports" "allow_web_and_ssh" {
  instance_name = aws_lightsail_instance.dualstack_instance.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }
}

output "lightsail_instance_name" {
  description = "The name of the Lightsail instance."
  value       = aws_lightsail_instance.dualstack_instance.name
}

output "lightsail_public_ipv4_address" {
  description = "The public IPv4 address of the Lightsail instance."
  value       = aws_lightsail_instance.dualstack_instance.public_ip_address
}

output "lightsail_ipv6_addresses" {
  description = "The IPv6 addresses assigned to the Lightsail instance."
  value       = aws_lightsail_instance.dualstack_instance.ipv6_addresses
}

output "lightsail_username" {
  description = "The default username for the selected Lightsail blueprint."
  value       = aws_lightsail_instance.dualstack_instance.username
}