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
  description = "AWS region where the Lightsail resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "lightsail_instance_name" {
  description = "Name of the Amazon Lightsail instance."
  type        = string
  default     = "example-lightsail-instance"
}

variable "lightsail_static_ip_name" {
  description = "Name of the Lightsail static IPv4 address."
  type        = string
  default     = "example-lightsail-static-ip"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID for the instance operating system."
  type        = string
  default     = "amazon_linux_2"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining the instance size."
  type        = string
  default     = "nano_3_0"
}

resource "aws_lightsail_instance" "this" {
  name              = var.lightsail_instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lightsail_static_ip" "this" {
  name = var.lightsail_static_ip_name
}

resource "aws_lightsail_static_ip_attachment" "this" {
  static_ip_name = aws_lightsail_static_ip.this.name
  instance_name  = aws_lightsail_instance.this.name
}

output "lightsail_instance_name" {
  description = "The name of the Lightsail instance."
  value       = aws_lightsail_instance.this.name
}

output "lightsail_static_ipv4_address" {
  description = "The allocated static IPv4 address."
  value       = aws_lightsail_static_ip.this.ip_address
}

output "lightsail_static_ip_name" {
  description = "The name of the Lightsail static IP."
  value       = aws_lightsail_static_ip.this.name
}