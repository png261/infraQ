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
  region = "us-east-2"
}

data "aws_availability_zones" "available" {
  provider = aws.aws
  state    = "available"
}

resource "aws_vpc" "msk" {
  provider = aws.aws

  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-msk-vpc"
  }
}

resource "aws_subnet" "msk_a" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.42.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "iac-eval-msk-subnet-a"
  }
}

resource "aws_subnet" "msk_b" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "iac-eval-msk-subnet-b"
  }
}

resource "aws_subnet" "msk_c" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.42.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "iac-eval-msk-subnet-c"
  }
}

resource "aws_security_group" "msk" {
  provider = aws.aws

  name        = "iac-eval-msk-sg"
  description = "Security group for the benchmark MSK cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Kafka broker TLS traffic within the VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-msk-sg"
  }
}

resource "aws_msk_cluster" "this" {
  provider = aws.aws

  cluster_name           = "iac-eval-msk-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.msk_a.id, aws_subnet.msk_b.id, aws_subnet.msk_c.id]
    security_groups = [aws_security_group.msk.id]
  }

  tags = {
    Name = "iac-eval-msk-cluster"
  }
}
