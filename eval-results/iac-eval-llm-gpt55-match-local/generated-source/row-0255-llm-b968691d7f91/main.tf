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

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for the Redshift cluster."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redshift-example-vpc"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-example-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-example-subnet-b"
  }
}

resource "aws_security_group" "redshift_sg" {
  name        = "redshift-example-sg"
  description = "Security group for example Redshift cluster and endpoint access"
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
    Name = "redshift-example-sg"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name        = "redshift-example-subnet-group"
  description = "Example Redshift subnet group with two subnets"

  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "redshift-example-subnet-group"
  }
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier = "redshift-example-cluster"
  database_name      = "exampledb"

  master_username = var.redshift_master_username
  master_password = var.redshift_master_password

  node_type    = "dc2.large"
  cluster_type = "single-node"

  port                     = 5439
  publicly_accessible      = false
  encrypted                = true
  enhanced_vpc_routing     = false
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name

  vpc_security_group_ids = [
    aws_security_group.redshift_sg.id
  ]

  skip_final_snapshot = true

  tags = {
    Name = "redshift-example-cluster"
  }
}

resource "aws_redshift_endpoint_access" "example" {
  endpoint_name          = "redshift-example-endpoint"
  cluster_identifier    = aws_redshift_cluster.example.cluster_identifier
  subnet_group_name      = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids = [aws_security_group.redshift_sg.id]

  depends_on = [
    aws_redshift_cluster.example
  ]
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.redshift_vpc.id
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group."
  value       = aws_redshift_subnet_group.redshift_subnet_group.name
}

output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.example.cluster_identifier
}

output "redshift_endpoint_access_name" {
  description = "Name of the Redshift endpoint access."
  value       = aws_redshift_endpoint_access.example.endpoint_name
}

output "redshift_endpoint_address" {
  description = "DNS address of the Redshift endpoint access."
  value       = aws_redshift_endpoint_access.example.address
}