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

# The benchmark intent names aws_ami, but the AWS provider's aws_ami
# resource registers an AMI from existing block-device snapshots and does not
# expose CPU topology arguments. To keep this configuration minimal and
# deployable without requiring a pre-existing snapshot, use the aws_ami data
# source to select the latest Amazon Linux 2 AMI and set the requested CPU
# topology on the aws_instance, where AWS supports core_count/threads_per_core.
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "amazon_linux_2" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "m5.xlarge"

  cpu_options {
    core_count       = 2
    threads_per_core = 2
  }

  tags = {
    Name = "iac-eval-amazon-linux-2"
  }
}
