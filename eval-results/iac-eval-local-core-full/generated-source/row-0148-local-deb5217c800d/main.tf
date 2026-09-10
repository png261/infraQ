terraform {
  required_version = ">= 1.6.0"

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

resource "aws_vpc" "redshift" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-benchmark-vpc"
  }
}

resource "aws_subnet" "redshift_a" {
  vpc_id            = aws_vpc.redshift.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "redshift-benchmark-subnet-a"
  }
}

resource "aws_subnet" "redshift_b" {
  vpc_id            = aws_vpc.redshift.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "redshift-benchmark-subnet-b"
  }
}

resource "aws_security_group" "redshift_endpoint" {
  name        = "redshift-benchmark-endpoint-sg"
  description = "Security group for Redshift endpoint access."
  vpc_id      = aws_vpc.redshift.id

  tags = {
    Name = "redshift-benchmark-endpoint-sg"
  }
}

resource "aws_redshift_subnet_group" "redshift" {
  name       = "redshift-benchmark-subnet-group"
  subnet_ids = [aws_subnet.redshift_a.id, aws_subnet.redshift_b.id]

  tags = {
    Name = "redshift-benchmark-subnet-group"
  }
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier        = "redshift-benchmark-cluster"
  database_name             = var.database_name
  master_username           = var.master_username
  master_password           = var.master_password
  node_type                 = var.node_type
  cluster_type              = "multi-node"
  number_of_nodes           = 2
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift.name
  skip_final_snapshot       = true

  tags = {
    Name = "redshift-benchmark-cluster"
  }
}

resource "aws_redshift_endpoint_access" "redshift" {
  endpoint_name          = "redshift-benchmark-endpoint"
  cluster_identifier     = aws_redshift_cluster.redshift.cluster_identifier
  subnet_group_name      = aws_redshift_subnet_group.redshift.name
  vpc_security_group_ids = [aws_security_group.redshift_endpoint.id]
}
