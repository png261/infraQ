terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
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
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "lightsail-bucket-client"
}

variable "lightsail_bucket_bundle_id" {
  description = "Bundle ID for the Lightsail bucket."
  type        = string
  default     = "small_1_0"
}

variable "lightsail_instance_blueprint_id" {
  description = "Blueprint ID for the Lightsail instance."
  type        = string
  default     = "amazon_linux_2"
}

variable "lightsail_instance_bundle_id" {
  description = "Bundle ID for the Lightsail instance."
  type        = string
  default     = "nano_3_0"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_lightsail_bucket" "bucket" {
  name      = "lightsail-access-bucket-${random_id.suffix.hex}"
  bundle_id = var.lightsail_bucket_bundle_id

  tags = {
    Name        = "lightsail-access-bucket"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_instance" "instance" {
  name              = var.lightsail_instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.lightsail_instance_blueprint_id
  bundle_id         = var.lightsail_instance_bundle_id

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_bucket_resource_access" "instance_bucket_access" {
  bucket_name   = aws_lightsail_bucket.bucket.name
  resource_name = aws_lightsail_instance.instance.name
}

output "lightsail_bucket_name" {
  description = "Name of the Lightsail bucket."
  value       = aws_lightsail_bucket.bucket.name
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance granted access to the bucket."
  value       = aws_lightsail_instance.instance.name
}

output "bucket_resource_access_id" {
  description = "ID of the Lightsail bucket resource access association."
  value       = aws_lightsail_bucket_resource_access.instance_bucket_access.id
}