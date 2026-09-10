terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-cluster"
}

variable "redshift_database_name" {
  description = "Initial database name for Redshift."
  type        = string
  default     = "dev"
}

variable "redshift_master_username" {
  description = "Master username for Redshift."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for Redshift. Must meet Redshift password requirements."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "redshift_node_type" {
  description = "Redshift node type."
  type        = string
  default     = "dc2.large"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-vpc"
  }
}

resource "aws_subnet" "redshift_private_subnet_a" {
  vpc_id            = aws_vpc.redshift_vpc.id
  cidr_block        = "10.50.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "redshift-private-subnet-a"
  }
}

resource "aws_subnet" "redshift_private_subnet_b" {
  vpc_id            = aws_vpc.redshift_vpc.id
  cidr_block        = "10.50.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "redshift-private-subnet-b"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name = "example-redshift-subnet-group"

  subnet_ids = [
    aws_subnet.redshift_private_subnet_a.id,
    aws_subnet.redshift_private_subnet_b.id
  ]

  tags = {
    Name = "example-redshift-subnet-group"
  }
}

resource "aws_security_group" "redshift_sg" {
  name        = "example-redshift-sg"
  description = "Security group for Redshift cluster"
  vpc_id      = aws_vpc.redshift_vpc.id

  ingress {
    description = "Allow Redshift access from within the VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.redshift_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "example-redshift-sg"
  }
}

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier = var.redshift_cluster_identifier
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password

  node_type       = var.redshift_node_type
  cluster_type    = "multi-node"
  number_of_nodes = 2

  port                    = 5439
  publicly_accessible     = false
  encrypted               = true
  enhanced_vpc_routing    = true
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.redshift_sg.id]

  skip_final_snapshot = true

  tags = {
    Name = "example-redshift-cluster"
  }
}

resource "aws_redshift_usage_limit" "concurrency_scaling_limit" {
  cluster_identifier = aws_redshift_cluster.redshift_cluster.cluster_identifier

  feature_type  = "concurrency-scaling"
  limit_type    = "time"
  amount        = 60
  period        = "daily"
  breach_action = "log"

  tags = {
    Name = "redshift-concurrency-scaling-60-minutes-daily"
  }
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.redshift_cluster.cluster_identifier
}

output "redshift_endpoint" {
  description = "The Redshift cluster endpoint."
  value       = aws_redshift_cluster.redshift_cluster.endpoint
}

output "concurrency_scaling_limit_minutes" {
  description = "Concurrency scaling usage limit in minutes per day."
  value       = aws_redshift_usage_limit.concurrency_scaling_limit.amount
}