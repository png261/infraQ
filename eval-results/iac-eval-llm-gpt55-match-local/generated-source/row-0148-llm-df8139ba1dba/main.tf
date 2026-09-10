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

variable "cluster_identifier" {
  description = "Redshift cluster identifier."
  type        = string
  default     = "example-redshift-cluster"
}

variable "database_name" {
  description = "Initial Redshift database name."
  type        = string
  default     = "dev"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "master_password" {
  description = "Master password for the Redshift cluster."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "node_type" {
  description = "Redshift node type."
  type        = string
  default     = "ra3.xlplus"
}

variable "redshift_port" {
  description = "Redshift database port."
  type        = number
  default     = 5439
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redshift-endpoint-vpc"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.50.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-b"
  }
}

resource "aws_security_group" "redshift_cluster_sg" {
  name        = "redshift-cluster-sg"
  description = "Security group for the Redshift cluster"
  vpc_id      = aws_vpc.redshift_vpc.id

  ingress {
    description     = "Allow Redshift traffic from endpoint security group"
    from_port       = var.redshift_port
    to_port         = var.redshift_port
    protocol        = "tcp"
    security_groups = [aws_security_group.redshift_endpoint_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redshift-cluster-sg"
  }
}

resource "aws_security_group" "redshift_endpoint_sg" {
  name        = "redshift-endpoint-sg"
  description = "Security group for the Redshift managed VPC endpoint"
  vpc_id      = aws_vpc.redshift_vpc.id

  ingress {
    description = "Allow Redshift access from within the VPC"
    from_port   = var.redshift_port
    to_port     = var.redshift_port
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
    Name = "redshift-endpoint-sg"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name        = "redshift-subnet-group"
  description = "Subnet group for Redshift cluster and endpoint"
  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "redshift-subnet-group"
  }
}

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  node_type       = var.node_type
  cluster_type    = "multi-node"
  number_of_nodes = 2

  port                    = var.redshift_port
  publicly_accessible     = false
  encrypted               = true
  enhanced_vpc_routing    = true
  skip_final_snapshot     = true
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name

  vpc_security_group_ids = [
    aws_security_group.redshift_cluster_sg.id
  ]

  tags = {
    Name = "example-redshift-cluster"
  }
}

resource "aws_redshift_endpoint_access" "redshift_endpoint_access" {
  endpoint_name          = "example-redshift-endpoint"
  cluster_identifier    = aws_redshift_cluster.redshift_cluster.cluster_identifier
  subnet_group_name     = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.redshift_endpoint_sg.id
  ]

  depends_on = [
    aws_redshift_cluster.redshift_cluster
  ]
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.redshift_cluster.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The standard Redshift cluster endpoint."
  value       = aws_redshift_cluster.redshift_cluster.endpoint
}

output "redshift_managed_endpoint_name" {
  description = "The Redshift managed endpoint access name."
  value       = aws_redshift_endpoint_access.redshift_endpoint_access.endpoint_name
}

output "redshift_managed_endpoint_address" {
  description = "The Redshift managed VPC endpoint address."
  value       = aws_redshift_endpoint_access.redshift_endpoint_access.address
}