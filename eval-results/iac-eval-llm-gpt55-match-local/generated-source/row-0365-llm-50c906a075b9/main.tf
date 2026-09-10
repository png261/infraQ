terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
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

variable "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "example-lightsail-instance"
}

variable "lightsail_key_pair_name" {
  description = "Name of the separate Lightsail SSH key pair."
  type        = string
  default     = "example-lightsail-ssh-key"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID for the instance operating system."
  type        = string
  default     = "ubuntu_22_04"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining instance size."
  type        = string
  default     = "nano_3_0"
}

resource "tls_private_key" "lightsail_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_lightsail_key_pair" "ssh_key" {
  name       = var.lightsail_key_pair_name
  public_key = tls_private_key.lightsail_ssh_key.public_key_openssh
}

resource "aws_lightsail_instance" "instance" {
  name              = var.lightsail_instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.ssh_key.name

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lightsail_static_ip" "static_ip" {
  name = "${var.lightsail_instance_name}-static-ip"
}

resource "aws_lightsail_static_ip_attachment" "static_ip_attachment" {
  static_ip_name = aws_lightsail_static_ip.static_ip.name
  instance_name  = aws_lightsail_instance.instance.name
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.instance.name
}

output "lightsail_public_ip" {
  description = "Static public IP address assigned to the Lightsail instance."
  value       = aws_lightsail_static_ip.static_ip.ip_address
}

output "lightsail_ssh_username" {
  description = "Default SSH username for the Ubuntu Lightsail blueprint."
  value       = "ubuntu"
}

output "private_key_pem" {
  description = "Private SSH key for connecting to the Lightsail instance. Save this securely."
  value       = tls_private_key.lightsail_ssh_key.private_key_pem
  sensitive   = true
}

output "ssh_command" {
  description = "SSH command example. Save the private key to a file first, then use this command."
  value       = "ssh -i lightsail-key.pem ubuntu@${aws_lightsail_static_ip.static_ip.ip_address}"
}