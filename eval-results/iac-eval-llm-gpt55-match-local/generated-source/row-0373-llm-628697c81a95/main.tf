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
  description = "Name of the Lightsail compute instance."
  type        = string
  default     = "lightsail-compute-service"
}

variable "disk_name" {
  description = "Name of the Lightsail storage disk."
  type        = string
  default     = "lightsail-storage-unit"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID for the instance operating system."
  type        = string
  default     = "ubuntu_22_04"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining compute size."
  type        = string
  default     = "nano_3_0"
}

variable "disk_size_gb" {
  description = "Size of the Lightsail storage disk in GB."
  type        = number
  default     = 32
}

resource "aws_lightsail_instance" "compute" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y util-linux

    mkdir -p /mnt/lightsail-storage

    if [ -b /dev/xvdf ]; then
      if ! blkid /dev/xvdf; then
        mkfs.ext4 /dev/xvdf
      fi

      mount /dev/xvdf /mnt/lightsail-storage

      if ! grep -q "/dev/xvdf /mnt/lightsail-storage" /etc/fstab; then
        echo "/dev/xvdf /mnt/lightsail-storage ext4 defaults,nofail 0 2" >> /etc/fstab
      fi
    fi
  EOF

  tags = {
    Name        = var.instance_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_disk" "storage" {
  name              = var.disk_name
  size_in_gb        = var.disk_size_gb
  availability_zone = var.availability_zone

  tags = {
    Name        = var.disk_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_disk_attachment" "storage_attachment" {
  disk_name     = aws_lightsail_disk.storage.name
  instance_name = aws_lightsail_instance.compute.name
  disk_path     = "/dev/xvdf"
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail compute instance."
  value       = aws_lightsail_instance.compute.name
}

output "lightsail_instance_public_ip" {
  description = "Public IP address of the Lightsail instance."
  value       = aws_lightsail_instance.compute.public_ip_address
}

output "lightsail_disk_name" {
  description = "Name of the attached Lightsail storage disk."
  value       = aws_lightsail_disk.storage.name
}

output "lightsail_disk_attachment_path" {
  description = "Device path where the Lightsail disk is attached."
  value       = aws_lightsail_disk_attachment.storage_attachment.disk_path
}