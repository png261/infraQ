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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-cluster"
}

variable "redshift_database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "exampledb"
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for the Redshift cluster."
  type        = string
  sensitive   = true
  default     = "ExamplePassword123!"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redshift-example-vpc"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id            = aws_vpc.redshift_vpc.id
  cidr_block        = "10.50.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "redshift-example-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id            = aws_vpc.redshift_vpc.id
  cidr_block        = "10.50.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "redshift-example-subnet-b"
  }
}

resource "aws_security_group" "redshift_sg" {
  name        = "redshift-example-security-group"
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
    Name = "redshift-example-security-group"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name        = "redshift-example-subnet-group"
  description = "Subnet group for example Redshift cluster"

  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "redshift-example-subnet-group"
  }
}

resource "aws_iam_role" "redshift_role" {
  name = "example-redshift-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "example-redshift-iam-role"
  }
}

resource "aws_iam_role_policy_attachment" "redshift_s3_readonly" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier = var.redshift_cluster_identifier
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password

  node_type    = "dc2.large"
  cluster_type = "single-node"

  port = 5439

  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.redshift_sg.id]

  publicly_accessible = false
  encrypted           = true

  iam_roles = [
    aws_iam_role.redshift_role.arn
  ]

  skip_final_snapshot = true

  depends_on = [
    aws_iam_role_policy_attachment.redshift_s3_readonly
  ]

  tags = {
    Name = "example-redshift-cluster"
  }
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.redshift_cluster.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The Redshift cluster endpoint."
  value       = aws_redshift_cluster.redshift_cluster.endpoint
}

output "redshift_iam_role_arn" {
  description = "The ARN of the IAM role associated with Redshift."
  value       = aws_iam_role.redshift_role.arn
}