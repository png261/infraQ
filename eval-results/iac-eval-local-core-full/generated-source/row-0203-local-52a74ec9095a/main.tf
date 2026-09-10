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
    Name = "benchmark-msk-vpc"
  }
}

resource "aws_subnet" "msk_a" {
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "benchmark-msk-subnet-a"
  }
}

resource "aws_subnet" "msk_b" {
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "benchmark-msk-subnet-b"
  }
}

resource "aws_subnet" "msk_c" {
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "benchmark-msk-subnet-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "benchmark-msk-sg"
  description = "Security group for benchmark MSK cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow Kafka TLS traffic within the VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-msk-sg"
  }
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/benchmark-cluster"
  retention_in_days = 7

  tags = {
    Name = "benchmark-msk-logs"
  }
}

resource "aws_msk_cluster" "benchmark" {
  cluster_name           = "benchmark-msk-cluster"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.msk_a.id, aws_subnet.msk_b.id, aws_subnet.msk_c.id]
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = {
    Name = "benchmark-msk-cluster"
  }
}
