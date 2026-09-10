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
  description = "AWS region where the Lightsail WordPress instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "instance_name" {
  description = "Name of the Lightsail WordPress instance."
  type        = string
  default     = "wordpress-lightsail"
}

variable "static_ip_name" {
  description = "Name of the Lightsail static IP."
  type        = string
  default     = "wordpress-lightsail-static-ip"
}

variable "key_pair_name" {
  description = "Name of the Lightsail SSH key pair."
  type        = string
  default     = "wordpress-lightsail-key"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID. The wordpress blueprint installs WordPress automatically."
  type        = string
  default     = "wordpress"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining instance size."
  type        = string
  default     = "nano_3_0"
}

resource "tls_private_key" "wordpress" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_lightsail_key_pair" "wordpress" {
  name       = var.key_pair_name
  public_key = tls_private_key.wordpress.public_key_openssh
}

resource "aws_lightsail_instance" "wordpress" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.wordpress.name

  tags = {
    Name        = var.instance_name
    Application = "WordPress"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lightsail_static_ip" "wordpress" {
  name = var.static_ip_name
}

resource "aws_lightsail_static_ip_attachment" "wordpress" {
  static_ip_name = aws_lightsail_static_ip.wordpress.name
  instance_name  = aws_lightsail_instance.wordpress.name
}

resource "aws_lightsail_instance_public_ports" "wordpress" {
  instance_name = aws_lightsail_instance.wordpress.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidrs     = ["0.0.0.0/0"]
  }
}

output "wordpress_instance_name" {
  description = "Name of the Lightsail WordPress instance."
  value       = aws_lightsail_instance.wordpress.name
}

output "wordpress_static_ip" {
  description = "Static public IP address attached to the WordPress Lightsail instance."
  value       = aws_lightsail_static_ip.wordpress.ip_address
}

output "wordpress_url" {
  description = "URL to access the WordPress site."
  value       = "http://${aws_lightsail_static_ip.wordpress.ip_address}"
}

output "ssh_command" {
  description = "SSH command to connect to the Lightsail WordPress instance."
  value       = "ssh -i wordpress-lightsail-key.pem bitnami@${aws_lightsail_static_ip.wordpress.ip_address}"
}

output "private_key_pem" {
  description = "Private SSH key for connecting to the Lightsail instance. Save this to wordpress-lightsail-key.pem and chmod 400 it."
  value       = tls_private_key.wordpress.private_key_pem
  sensitive   = true
}