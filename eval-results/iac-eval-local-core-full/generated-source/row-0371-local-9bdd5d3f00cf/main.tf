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

resource "aws_lightsail_disk" "benchmark" {
  name              = "benchmark-lightsail-disk"
  size_in_gb        = 8
  availability_zone = data.aws_availability_zones.available.names[0]
}
