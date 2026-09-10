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

variable "availability_zone" {
  description = "Availability Zone for the Lightsail instance and disks."
  type        = string
  default     = "us-east-1a"
}

variable "instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "example-lightsail-instance"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID for the instance operating system or application."
  type        = string
  default     = "ubuntu_22_04"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining instance size."
  type        = string
  default     = "nano_3_0"
}

variable "instance_user_data" {
  description = "User data script for the Lightsail instance."
  type        = string
  default     = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOF
}

variable "attached_disks" {
  description = "Map of Lightsail disks to create and attach to the instance."
  type = map(object({
    size_in_gb = number
    disk_path  = string
  }))

  default = {
    data_disk_1 = {
      size_in_gb = 8
      disk_path  = "/dev/xvdf"
    }

    data_disk_2 = {
      size_in_gb = 16
      disk_path  = "/dev/xvdg"
    }

    data_disk_3 = {
      size_in_gb = 32
      disk_path  = "/dev/xvdh"
    }
  }
}

resource "aws_lightsail_instance" "this" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  user_data         = var.instance_user_data

  tags = {
    Name        = var.instance_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_disk" "this" {
  for_each = var.attached_disks

  name              = "${var.instance_name}-${each.key}"
  size_in_gb        = each.value.size_in_gb
  availability_zone = var.availability_zone

  tags = {
    Name        = "${var.instance_name}-${each.key}"
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_disk_attachment" "this" {
  for_each = var.attached_disks

  disk_name     = aws_lightsail_disk.this[each.key].name
  instance_name = aws_lightsail_instance.this.name
  disk_path     = each.value.disk_path
}

output "lightsail_instance_name" {
  description = "Name of the created Lightsail instance."
  value       = aws_lightsail_instance.this.name
}

output "lightsail_instance_arn" {
  description = "ARN of the created Lightsail instance."
  value       = aws_lightsail_instance.this.arn
}

output "attached_disk_names" {
  description = "Names of the Lightsail disks attached to the instance."
  value       = [for disk in aws_lightsail_disk.this : disk.name]
}

output "attached_disk_paths" {
  description = "Disk attachment paths."
  value       = {
    for key, attachment in aws_lightsail_disk_attachment.this :
    key => attachment.disk_path
  }
}