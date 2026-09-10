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
  description = "AWS region where Lightsail resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability Zone for the Lightsail instance and disk."
  type        = string
  default     = "us-east-1a"
}

variable "instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "example-lightsail-instance"
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

variable "disk_path" {
  description = "Device path where the disk will be attached to the Lightsail instance."
  type        = string
  default     = "/dev/xvdf"
}

resource "aws_lightsail_instance" "example" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = "ubuntu_22_04"
  bundle_id         = "nano_3_0"

  tags = {
    Name        = var.instance_name
    Environment = "example"
  }
}

resource "aws_lightsail_disk" "example" {
  name              = var.disk_name
  size_in_gb        = var.disk_size_gb
  availability_zone = var.availability_zone

  tags = {
    Name        = var.disk_name
    Environment = "example"
  }
}

resource "aws_lightsail_disk_attachment" "example" {
  disk_name     = aws_lightsail_disk.example.name
  instance_name = aws_lightsail_instance.example.name
  disk_path     = var.disk_path
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.example.name
}

output "lightsail_disk_name" {
  description = "Name of the Lightsail disk."
  value       = aws_lightsail_disk.example.name
}

output "lightsail_disk_attachment_path" {
  description = "Device path where the disk is attached."
  value       = aws_lightsail_disk_attachment.example.disk_path
}