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

resource "aws_vpc" "msk" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "msk-serverless-benchmark-vpc"
  }
}

resource "aws_subnet" "broker_a" {
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "msk-serverless-benchmark-subnet-a"
  }
}

resource "aws_subnet" "broker_b" {
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "msk-serverless-benchmark-subnet-b"
  }
}

resource "aws_subnet" "broker_c" {
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "msk-serverless-benchmark-subnet-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "msk-serverless-benchmark-sg"
  description = "Security group for the benchmark MSK Serverless cluster"
  vpc_id      = aws_vpc.msk.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "msk-serverless-benchmark-sg"
  }
}

resource "aws_msk_serverless_cluster" "this" {
  cluster_name = "msk-serverless-benchmark"

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.broker_a.id,
      aws_subnet.broker_b.id,
      aws_subnet.broker_c.id,
      aws_subnet.broker_a.id,
      aws_subnet.broker_b.id,
      aws_subnet.broker_c.id,
    ]
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = {
    Name = "msk-serverless-benchmark"
  }
}

output "msk_serverless_cluster_arn" {
  description = "ARN of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.arn
}

output "msk_serverless_bootstrap_brokers_sasl_iam" {
  description = "IAM SASL bootstrap broker endpoints for the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam
}
