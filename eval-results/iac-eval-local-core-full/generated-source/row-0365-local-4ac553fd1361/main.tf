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

resource "aws_lightsail_key_pair" "ssh" {
  name       = "benchmark-lightsail-key"
  public_key = var.lightsail_public_key
}

resource "aws_lightsail_instance" "example" {
  name              = "benchmark-lightsail-instance"
  availability_zone = "us-east-1a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
  key_pair_name     = aws_lightsail_key_pair.ssh.name
}
