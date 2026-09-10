terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_lightsail_instance" "example" {
  name              = "example-lightsail-instance"
  availability_zone = local.availability_zone
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
}

resource "aws_lightsail_disk" "example" {
  name              = "example-lightsail-disk"
  size_in_gb        = 8
  availability_zone = local.availability_zone
}

resource "aws_lightsail_disk_attachment" "example" {
  disk_name     = aws_lightsail_disk.example.name
  instance_name = aws_lightsail_instance.example.name
  disk_path     = "/dev/xvdf"
}
