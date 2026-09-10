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

data "aws_caller_identity" "current" {}

variable "aws_region" {
  description = "AWS region to deploy the Redshift cluster into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-2-node-cluster"
}

variable "database_name" {
  description = "Initial Redshift database name."
  type        = string
  default     = "devdb"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "master_password" {
  description = "Master password for the Redshift cluster. Must meet Redshift password requirements."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "node_type" {
  description = "Redshift node type."
  type        = string
  default     = "dc2.large"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-vpc"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-b"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name       = "example-redshift-subnet-group"
  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "example-redshift-subnet-group"
  }
}

resource "aws_security_group" "redshift_sg" {
  name        = "example-redshift-security-group"
  description = "Security group for the Redshift cluster"
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
    Name = "example-redshift-security-group"
  }
}

resource "aws_redshift_cluster" "this" {
  cluster_identifier = var.cluster_identifier

  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password

  node_type       = var.node_type
  cluster_type    = "multi-node"
  number_of_nodes = 2

  port = 5439

  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.redshift_sg.id]

  publicly_accessible    = false
  encrypted              = true
  skip_final_snapshot    = true
  enhanced_vpc_routing   = true
  allow_version_upgrade  = true

  tags = {
    Name = "example-redshift-2-node-cluster"
  }
}

resource "aws_redshift_resource_policy" "this" {
  resource_arn = aws_redshift_cluster.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCurrentAccountDescribeAndCredentials"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action = [
          "redshift:DescribeClusters",
          "redshift:GetClusterCredentials"
        ]

        Resource = aws_redshift_cluster.this.arn
      }
    ]
  })
}

output "redshift_cluster_id" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.this.id
}

output "redshift_cluster_arn" {
  description = "The Redshift cluster ARN."
  value       = aws_redshift_cluster.this.arn
}

output "redshift_cluster_endpoint" {
  description = "The Redshift cluster endpoint."
  value       = aws_redshift_cluster.this.endpoint
}

output "redshift_resource_policy_id" {
  description = "The Redshift resource policy ID."
  value       = aws_redshift_resource_policy.this.id
}