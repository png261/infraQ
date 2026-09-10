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
  alias  = "aws"
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  provider = aws.aws
  state    = "available"
}

resource "aws_vpc" "msk" {
  provider = aws.aws

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "serverless-msk-vpc"
  }
}

resource "aws_subnet" "msk_a" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "serverless-msk-subnet-a"
  }
}

resource "aws_subnet" "msk_b" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "serverless-msk-subnet-b"
  }
}

resource "aws_subnet" "msk_c" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "serverless-msk-subnet-c"
  }
}

resource "aws_security_group" "msk" {
  provider = aws.aws

  name        = "serverless-msk-sg"
  description = "Security group for serverless MSK benchmark cluster"
  vpc_id      = aws_vpc.msk.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "serverless-msk-sg"
  }
}

resource "aws_msk_serverless_cluster" "this" {
  provider = aws.aws

  cluster_name = "benchmark-serverless-msk"

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.msk_a.id,
      aws_subnet.msk_b.id,
      aws_subnet.msk_c.id,
    ]
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = {
    Name = "benchmark-serverless-msk"
  }
}
